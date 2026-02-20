using Distributed

using Serialization

include("../src/MonteCarlo.jl")
include("../src/DMonteCarlo.jl")
include("../src/CMonteCarlo.jl")

using .MonteCarlo
using .DMonteCarlo: GridTorsionsCV, AsyncSparseGridBias, SinglSparseGridBias, MetadynamicsLogger, rotmove!
using .CMonteCarlo: monsystemsetup

numworkers = 10
if nworkers() == 1
    addprocs(numworkers) # или numworkers
end

@everywhere begin
    using Pkg
    Pkg.activate(".")

    using Molly
    # Сначала подключаем файлы, чтобы типы были известны всем
    if !@isdefined(MonteCarlo)
        include("../src/MonteCarlo.jl")
        include("../src/DMonteCarlo.jl")
        include("../src/CMonteCarlo.jl")
    end
    # Обращаемся к модулям явно, если они конфликтуют
    using .MonteCarlo
    using .DMonteCarlo
    using .CMonteCarlo
end

gnasyn = 10_000
gnumrounds = 1_000
# allsimuleiterates = gnasyn * gnumrounds * numworkers

mcsys, mcsim, numcv = monsystemsetup("diala.sdf", singlmode=false)

globalbiasdata = mcsys.loggers.metac.bias.data

maxcontent = 200
const inworkerchanels = Dict(w => RemoteChannel(() -> Channel{Dict{NTuple{numcv,Int16},Float32}}(maxcontent)) for w in workers())
const outerchannel = RemoteChannel(() -> Channel{Pair{Int64,Dict{NTuple{numcv,Int16},Float32}}}(1))

@everywhere begin
    numcv = $numcv
    function workerprocess(mcsys, mcsim, nasyn, numrounds, outch, inchdict)
        stepsdone = 0
        my_id = myid()
        myinbox = inchdict[my_id]
        biass = mcsys.loggers.metac.bias
        for r in 1:numrounds
            # 1. СИМУЛЯЦИЯ (Чистая физика)
            # Прогоняем n_asyn шагов. Molly просто делает свою работу.
            Molly.simulate!(mcsys, mcsim, nasyn)
            stepsdone += nasyn
            # 2. СИНХРОНИЗАЦИЯ (Сеть)
            # Достаем то, что накопил локальный логгер за этот цикл
            # Отправляем на мастер. put! - ждущий
            localdeltasize = length(biass.delta)
            if !isempty(biass.delta)
                put!(outch, my_id => copy(biass.delta))
                empty!(biass.delta)
            end

            # Запрашиваем обновление с мастера
            received_count = 0
            while isready(myinbox)
                remotedelta = take!(myinbox)
                received_count += length(remotedelta)
                mergewith!(+, biass.data, remotedelta)
            end

            if r % 10 == 0 # Не спамим в консоль слишком часто
                println("Create/Recive : $(localdeltasize)/$(received_count). Total knowledge: $(length(biass.data)). Finished $stepsdone steps")
                flush(stdout)
            end
        end
        # сигал что всё
        put!(outch, my_id => Dict{NTuple{numcv,Int16},Float32}())
        println("Worker $my_id sent EXIT signal")
        flush(stdout)
        return stepsdone
    end
end

function run_comuna(endes, globalbias, inworkerchanels, outerchannel)
    processed = 0
    println("Master: Comuna started. Waiting for $endes packets...")
    #@async while processed < endes
    start_time = time()
    active_ids = workers()
    while !isempty(active_ids)
        # Ждем пакет от любого воркера
        wokaid, somedelta = take!(outerchannel)
        # когда вока отстрелялся
        if isempty(somedelta)
            setdiff!(active_ids, [wokaid])
            println("Master: Worker $wokaid finished. Active: $(length(active_ids))")
            flush(stdout)
            continue
        end
        # Обновляем глобальную копию на мастере (для истории/сохранения)
        mergewith!(+, globalbias, somedelta)
        # рассыля
        for wid in active_ids
            if wid != wokaid
                # Кладем в инбокс. Если воркер не забирает (ящик полон), 
                # put! заблокирует этот цикл мастера.	
                @async put!(inworkerchanels[wid], somedelta)
            end
        end
        processed += 1
        if processed % 200 == 0 # Каждые 100 пакетов
            # Сохраняем промежуточный результат
            serialize("bias_checkpoint.jls", (globalbias, mcsys.coords,
                @fetchfrom 2 Main.mcsys.coords,
                @fetchfrom 3 Main.mcsys.coords,
                @fetchfrom 4 Main.mcsys.coords,
                @fetchfrom 5 Main.mcsys.coords,
                @fetchfrom 6 Main.mcsys.coords,
                @fetchfrom 7 Main.mcsys.coords,
                @fetchfrom 8 Main.mcsys.coords,
                @fetchfrom 9 Main.mcsys.coords,
                @fetchfrom 10 Main.mcsys.coords,
                @fetchfrom 11 Main.mcsys.coords))
            println("Master: Checkpoint saved. Progress: $(round(100*processed/endes, digits=2))%")
            flush(stdout)
        end
        # Красивый вывод каждые N пакетов
        if processed % 50 == 0
            elapsed = time() - start_time
            rate = processed / elapsed  # пакетов в секунду
            # Рассчитываем ETA (оставшееся время)
            remaining = endes - processed
            eta_sec = remaining / rate

            @info "Progress" processed = processed rate = round(rate, digits=2) elapsed = round(elapsed, digits=1) ETA = round(eta_sec / 60, digits=2)
            flush(stdout)
        end
    end
    println("Master: Comuna finished.")
    flush(stdout)
end

# ЗАПУСК
# 1. Запускаем коммуникатор в фоне
# Мы ожидаем gnumrounds от каждого из numworkers
mastertask = @async run_comuna(gnumrounds * numworkers, globalbiasdata, inworkerchanels, outerchannel)

# 2. Запускаем воркеров
futures = [@spawnat w workerprocess(mcsys, mcsim, gnasyn, gnumrounds, outerchannel, inworkerchanels) for w in workers()]
