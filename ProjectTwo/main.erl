% @author Mathias.Brekkan and ruiyang

-module(main).
-export([start/3, boss/4, nodeInit/1, sendAllRegAcc/6]).


start(NumberOfNodes, GridType, AlgorithmType) ->
    Pid = spawn(main, boss, [NumberOfNodes, GridType, AlgorithmType, []]),
    register(master, Pid),
    createNodes(NumberOfNodes, node()).





createNodes(0, _) -> ok;
createNodes(NumberOfNodesLeft, MasterNode) ->
    spawn(main, nodeInit, [MasterNode]),
    createNodes(NumberOfNodesLeft - 1, MasterNode).




getRandomNumber(Min, Max) ->
    crypto:rand_uniform(Min, Max + 1).

getOneWithRandomSign() ->
    case getRandomNumber(0, 1) of
        0 ->
            1;
        1 ->
            -1
    end.



sendAllRegAcc(_, _, _, _, _, []) -> ok;
sendAllRegAcc(NumberOfNodes, CurrentIndex, Nodes, GridType, AlgorithmType, [Node | Tail]) ->
    RandAccessDimIndex = getRandomNumber(0, 5),
    RandNodeIndex = getRandomNumber(1, round(NumberOfNodes/6)),
    Node ! {allRegAcc, CurrentIndex, GridType, AlgorithmType, Nodes, RandAccessDimIndex, RandNodeIndex},
    sendAllRegAcc(NumberOfNodes, CurrentIndex + 1, Nodes, GridType, AlgorithmType, Tail).



boss(NumberOfNodes, GridType, AlgorithmType, Nodes) ->
    case NumberOfNodes == length(Nodes) of
        true ->
            sendAllRegAcc(NumberOfNodes, 1, Nodes, GridType, AlgorithmType, Nodes),
            StartTime = erlang:timestamp(),
            if
                AlgorithmType == "Gossip" ->
                    lists:nth(getRandomNumber(1, length(Nodes)), Nodes) ! {gossip, "Advanced message"},
                    bossWaitForFinish(gossip, length(Nodes), GridType, StartTime, NumberOfNodes);
                AlgorithmType == "PushSum" ->
                    lists:nth(getRandomNumber(1, length(Nodes)), Nodes) ! {pushSum, 0, 0},
                    bossWaitForFinish(pushSum, length(Nodes), GridType, StartTime, Nodes)
            end;

            
        false ->
            ok
    end,
    receive
        {reg, Slave_ID} -> % Register node
            % io:fwrite("Node registered\n"),
            boss(NumberOfNodes, GridType, AlgorithmType, [Slave_ID | Nodes])
    end.

bossWaitForFinish(gossip, InputSize, GridType, StartTime, NumberOfNodesLeft) ->
    if
        NumberOfNodesLeft == 0 ->
            %%io:format("Finished, Program run time:~fs~n", [timer:now_diff(erlang:timestamp(), StartTime) / 1000000]);
            {ok, S} = file:open("results", [append]),
            io:format(S, "~p   ~p   gossip   ~f~n", [InputSize, GridType, timer:now_diff(erlang:timestamp(), StartTime) / 1000000]);
        true ->
            receive
                {finito} ->
                    bossWaitForFinish(gossip, InputSize, GridType, StartTime, NumberOfNodesLeft - 1)
            end
    end;

bossWaitForFinish(pushSum, InputSize, GridType, StartTime, Nodes) ->
    receive
        {finito} ->
            %%io:format("Program run time: ~fs~n", [timer:now_diff(erlang:timestamp(), StartTime) / 1000000]),
            {ok, S} = file:open("results", [append]),
            io:format(S, "~p   ~p   pushsum   ~f~n", [InputSize, GridType, timer:now_diff(erlang:timestamp(), StartTime) / 1000000]),
            terminateAllNodes(Nodes)
    end.


terminateAllNodes([]) ->
    ok;
terminateAllNodes(Nodes) ->
    hd(Nodes) ! {kill},
    terminateAllNodes(tl(Nodes)).

nodeInit(MasterNode) ->
    {master, MasterNode} ! {reg, self()},
    receive
        {allRegAcc, Index, GridType, AlgorithmType, Nodes, RandAccessDimIndex, RandNodeIndex} ->
            case AlgorithmType of
                "Gossip" ->
                    gossip(GridType, MasterNode, Index, Nodes, "", 0, RandAccessDimIndex, RandNodeIndex);
                "PushSum" ->
                    pushSum(GridType, MasterNode, Index, Nodes, Index, 1, 1, [], RandAccessDimIndex, RandNodeIndex)
            end
    end.

pushSum(GridType, MasterNode, Index, Nodes, Sum, Weight, Iteration, Ratios, RandAccessDimIndex, RandNodeIndex) ->
    receive
        {kill} ->
            ok;


        {pushSum, AddedSum, AddedWeight} ->
            NewSum = (Sum + AddedSum) / 2,
            NewWeight = (Weight + AddedWeight) / 2,
            case length(Ratios) of 
                3 ->
                    IsFinished = (abs(lists:nth(2, Ratios) - lists:nth(1, Ratios)) < 0.0000000001) and (abs(lists:nth(3, Ratios) - lists:nth(2, Ratios)) < 0.0000000001),
                    if
                        IsFinished ->
                            io:format("Program finished~n"),
                            io:format("The final sum: ~p~n", [NewSum / NewWeight]),
                            NewRatios = [],
                            {master, MasterNode} ! {finito};
                        
                        true ->
                           NewRatios = tl(Ratios) ++ [NewSum / NewWeight]
                    end;
                _Else ->
                    NewRatios = Ratios ++ [NewSum / NewWeight]
            end,


            Failed = (crypto:rand_uniform(1, 4) rem 4) == 0,
            if
                Failed ->
                    ok;
                true ->
                    lists:nth(getRandomNeighbour(GridType, Index, Nodes, RandAccessDimIndex, RandNodeIndex), Nodes) ! {pushSum, NewSum, NewWeight}
            end,
            pushSum(GridType, MasterNode, Index, Nodes, NewSum, NewWeight, Iteration + 1, NewRatios, RandAccessDimIndex, RandNodeIndex)
    end.

            
    
gossip(GridType, MasterNode, Index, Nodes, ActualMessage, RecievedMessageCount, RandAccessDimIndex, RandNodeIndex) ->
    TerminationCount = 10,
    if
        RecievedMessageCount < TerminationCount ->
            receive
                {gossip, Message} ->
                    Failed = (crypto:rand_uniform(1, 4) rem 4) == 0,
                    if
                        Failed ->
                            ok;
                        true ->
                            lists:nth(getRandomNeighbour(GridType, Index, Nodes, RandAccessDimIndex, RandNodeIndex), Nodes) ! {gossip, Message}
                    end,
                    
                    if
                        RecievedMessageCount > 0 ->
                            {master, MasterNode} ! {finito};
                        true ->
                            ok
                    end,
                    gossip(GridType, MasterNode, Index, Nodes, Message, RecievedMessageCount + 1, RandAccessDimIndex, RandNodeIndex)
                after 50 ->
                    if
                        RecievedMessageCount > 0 ->
                            lists:nth(getRandomNeighbour(GridType, Index, Nodes, RandAccessDimIndex, RandNodeIndex), Nodes) ! {gossip, ActualMessage},
                            gossip(GridType, MasterNode, Index, Nodes, ActualMessage, RecievedMessageCount, RandAccessDimIndex, RandNodeIndex);
                        true ->
                            gossip(GridType, MasterNode, Index, Nodes, ActualMessage, RecievedMessageCount, RandAccessDimIndex, RandNodeIndex)
                    end
            end;
        true ->
            ok
    end.



adjustToLinearBounds(TargetIndex, Count) ->
    if
        TargetIndex > Count ->
            TargetIndex - Count;
        TargetIndex < 1 ->
            Count + TargetIndex;
        true ->
            TargetIndex
    end.



getRandomNeighbour(GridType, Index, Nodes, RandAccessDimIndex, RandNodeIndex) ->
    NodeCount = length(Nodes),
    case GridType of
        "FullNetwork" ->
            adjustToLinearBounds(Index + getRandomNumber(1, NodeCount), NodeCount);
        "Line" ->
            adjustToLinearBounds(Index + getOneWithRandomSign(), NodeCount);
        "2dGrid" ->
            GridWidth = round(math:sqrt(NodeCount)),
            getRandomGridNeighbour(GridWidth, Index);
        "Imperfect3dGrid" ->
            GridSectionSize = round(NodeCount/6),
            GridWidth = round(math:sqrt(GridSectionSize)),
            InterpolatedIndex = 6 - floor(Index / GridSectionSize),
            RandNum = getRandomNumber(1, 9),
            if
                RandNum == 1 ->
                    RandAccessDimIndex * GridSectionSize + RandNodeIndex;
                true ->
                    RandAccessDimIndex * GridSectionSize + getRandomGridNeighbour(GridWidth, InterpolatedIndex)
            end
    end.



getRandomGridNeighbour(GridWidth, Index) ->
    OffsetX = getRandomNumber(-1, 1),
    OffsetY = getRandomNumber(-1, 1),
    XCoord = Index rem GridWidth,
    YCoord = math:floor(Index/GridWidth),
    NewXCoord = adjustToLinearBounds(XCoord + OffsetX, GridWidth),
    NewYCoord = adjustToLinearBounds(YCoord + OffsetY, GridWidth),
    round(GridWidth * (NewXCoord - 1) + NewYCoord).
