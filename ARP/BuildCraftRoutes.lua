function pas_delay_cost(cTime)
    if cTime==0 then return 0 end 
    local time = {1,2,4,12,24}
    local index = {1,1.5,2,3,5}
    for i=1,#time do
        if cTime<=time[i]*60 then 
            return index[i]
        end 
    end 
    error('This passenger should be canceled for delay more than 24 hours')
    return false
end 

function flight_delay_cost(cFlight, delay)
    --(delay fixed cost 1200 + delay time cost 30 * hours + pas delay cost) * wt
    --if cFlight.wt then  
        local cost = 0
        if delay>0 then 
            if cFlight.dis then 
                cost = (cost + delay / 2 + (pas_delay_cost(delay+120)-1.5) * cFlight.old.pas) * cFlight.wt
            else 
                cost = (1200 + delay / 2 + pas_delay_cost(delay) * cFlight.old.pas) * cFlight.wt --/60*30
            end 
        end 
       
        return cost
     --   return delay>0 and (1200 + delay / 2 + pas_delay_cost(delay) * cFlight.old.pas) * cFlight.wt or 0 --/60*30
    --end 
    --return 0 
end

function time_check_airport(port, time)
    if port.tw then 
        if port.tw[2]>1440 then 
            return not (time%1440<port.tw[1] and time%1440>port.tw[2]%1440)
        else
            return time%1440<port.tw[1] or time%1440>port.tw[2] 
        end 
    end
    return true
end 

function craft_swap_cost(cFlight, ncraft)
    local cost = 0 
    if cFlight.old[1]~=ncraft then
        if cFlight.old.atp~=ncraft.atp then
            local typeSwap = {{0,1,2,3},{1,0,1.5,2.5},{2,1.5,0,2},{3,2.5,2,0}}
            cost = cost + 300 * typeSwap[ncraft.atp][cFlight.old.atp]        
        end 
        if cFlight.old.pas-ncraft.seats>0 then
            if cFlight.dis then 
                cost = cost + (cFlight.old.pas - ncraft.seats) * (6-1.5)
            else 
                cost = cost + (cFlight.old.pas - ncraft.seats) * 6
            end 
        end 
        return cost * cFlight.wt ---passenger cancel because of seats decresing
    end 
    return cost 
end 

local function Dominated(label1, label2)
    if #label1==#label2 then 
        for i=2,#label1-1 do
            if label1[i]~=label2[i] then 
                return false
            end 
        end 
        return label1.cost<=label2.cost  and label1.cut1<=label2.cut1 and label1.cut2<=label2.cut2 
    end 
    return false
end 

function label_extend(flight1, flight2, craft, index)
    --every flight has a label set, include a set of labels <totalcost, delay time>, which has no dominance
    --from the start airport to base airport?
    for _, label in ipairs(flight1.labels) do
        for t=1,3 do
            local tag = {cut1=label.cut1,cut2=label.cut2, cuts=DeepCopy(label.cuts)}  --cost=label.cost}--,  --cut=label.cut, cuts=DeepCopy(label.cuts), delay=label.delay,}
            if flight2.port2 then  --如果flight2不是终点
                local qcut = 0
                if t==1 then 
                    tag.delay = math.max(0, flight1.time2 + label.delay + flight1.gtime - flight2.time1)
                elseif label.delay+flight1.time2+flight1.gtime>flight2.time1 then
                    if t==2 then
                        if flight1.gtime>airports[flight1.port2].turn[craft.atp] then  ----for the gtime < airports[flight1.port2].turn[craft.atp] situation
                            tag.delay = math.max(0, flight1.time2 + label.delay + airports[flight1.port2].turn[craft.atp] - flight2.time1)
                        else
                            goto continue
                        end 
                    elseif t==3 then
                        --if flight1.gtime>math.ceil(airports[flight1.port2].turn[craft.atp]*2/3) then    ---there are two situations,one all cut2 has been cutted, or part of   ignore gtime<min turntime
                        if flight1.gtime>airports[flight1.port2].turn[craft.atp] then    ---there are two situations,one all cut2 has been cutted, or part of
                            tag.delay = math.max(0, flight1.time2 + label.delay + math.ceil(airports[flight1.port2].turn[craft.atp]*2/3) - flight2.time1)
                            qcut = tag.delay>0 and math.floor(airports[flight1.port2].turn[craft.atp]*1/3) --or airports[flight1.port2].turn[craft.atp] - flight2.time1 + flight1.time2 + label.delay
                        else 
                            break
                        end 
                    end 
                    if flight1.date==1 then 
                        tag.cut1 = tag.cut1 + 1
                    elseif flight1.date==2 then  
                        tag.cut2 = tag.cut2 + 1
                    end 
                    tag.cuts[#label-1] = qcut 
                else 
                    break
                end 
                
                --这个delay是当前航班的delay，之前航班的delay成本已经计算进去了
                if tag.delay>1440 then break end
                if flight2.time2+tag.delay+math.ceil(airports[flight2.port2].turn[craft.atp]*2/3)>craft.dayN then break end
                ----机场关闭约束
                if airports[flight2.port1].tw and (not time_check_airport(airports[flight2.port1], flight2.time1+tag.delay)) then 
                    break
                end
                if airports[flight2.port2].tw and (not time_check_airport(airports[flight2.port2], flight2.time2+tag.delay)) then
                    break
                end 
                --add the delay cost and aircraft change cost
                tag.cost = label.cost + flight_delay_cost(flight2, tag.delay) + craft_swap_cost(flight2, craft) + qcut * 20   ---flight2.dual     
                if flight1.date<flight2.date then 
                    if flight1.port2~=craft.base[1] then
                        tag.cost = tag.cost + 2000
                    end 
                end 
            else
                tag = {cost=label.cost, delay=label.delay, cut1=label.cut1, cuts=DeepCopy(label.cuts)}
                if tag.delay+flight1.time2+flight1.gtime>craft.dayN then
                    if tag.delay+flight1.time2+math.ceil(airports[flight1.port2].turn[craft.atp]*2/3)<=craft.dayN then 
                        if flight1.date==1 then 
                            tag.cut1 = tag.cut1 + 1
                        elseif flight2.date==2 then
                            tag.cut1 = tag.cut1 + 1
                        end 
                        local qcut = math.max(0, flight1.time2+tag.delay+airports[flight1.port2].turn[craft.atp]-craft.dayN)
                        tag.cost = tag.cost + qcut * 20 
                        table.insert(tag.cuts, qcut)
                    else
                        goto continue
                    end 
                end 
            end 
            
            for i=1,#label do
                table.insert(tag, label[i])
            end 
            table.insert(tag, index)
            
            --if not flight2.port2 then 
                local dominated 
                for i,ir in ipairs(flight2.labels) do
                    if Dominated(ir, tag) then 
                        dominated = true
                        break
                    end 
                end 
                if not dominated then 
                    local i = 1
                    while i<=#flight2.labels do
                        if Dominated(tag, flight2.labels[i]) then 
                            table.remove(flight2.labels, i)
                            i = i - 1
                        end 
                        i = i + 1
                    end 
                end 
--                while true do 
--                    if i>#flight2.labels then break end 
--                    if Dominated(flight2.labels[i], tag) then 
--                        tag = nil
--                        break
--                    elseif Dominated(tag, flight2.labels[i]) then 
--                        table.remove(flight2.labels, i)
--                        i = i - 1
--                    end 
--                    i = i + 1
--                end 
            --end 
            table.insert(flight2.labels, tag)
            if tag and tag.delay==0 or not flight2.port2 then break end 
            ::continue::
        end 
    end
end 

function build_craft_routes(output)
    routes = {}
    for c=1,#crafts do --#crafts do
        for i,ir in ipairs(fSet[c].order) do
            for j,jr in ipairs(fSet[c].adj[ir]) do
               label_extend(fSet[c][ir], fSet[c][jr], crafts[c], jr)
            end
        end
     
        for i,label in ipairs(fSet[c][#fSet[c]].labels) do
            if #label>2 then 
                local route = {cost=label.cost, craft=crafts[c].id,cut1=label.cut1,cut2=label.cut2,cuts=label.cuts}
                for i=2,#label-1 do 
                    table.insert(route, fSet[c][label[i]])
                end 
                table.insert(routes, route)
            end 
        end
   
        for i=1,#fSet[c] do
            fSet[c][i].labels = {}
        end 
        if output then  
            print('finish', c)
        end 
    end 
     
end 