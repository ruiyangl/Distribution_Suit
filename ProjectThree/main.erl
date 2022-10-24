% @author Mathias Brekkan and Ruiyang Li

-module(main).
-export([start/3, start/2, master/4, operate/8, nodeInit/2, join/1, createNodes/2]).
-import(methods, [getRandomNumber/2, getRandomString/1, getHash/1, adjustToLinearBounds/2, getM/0, getCircleSize/0]).
-import(test, [printList/1]).
-include("records.hrl"). 



start(NumberOfNodes, NumberOfRequests, Master) ->
    start(NumberOfNodes, NumberOfRequests),
    createNodes(NumberOfNodes, Master).


createNodes(0, _) ->
    io:format("All nodes are created~n");
createNodes(NumberOfNodes, Master) ->
    join(Master),
    createNodes(NumberOfNodes - 1, Master).



start(NumberOfNodes, NumberOfRequests) ->
    %%% M = math:ceil(math:log2(NumberOfNodes * NumberOfRequests * 2)),
    Pid = spawn(main, master, [NumberOfNodes, NumberOfRequests, getM(), []]),
    register(master, Pid),
    createFirstNode(master).

master(NumberOfNodes, NumberOfRequests, M, Nodes) ->
    % NodesSortedByHid = lists:keysort(1, maps:to_list(NodesMap)),
    
    %%% sendAllRegAcc(NumberOfNodes, 1, NumberOfRequests, Nodes, Nodes),
    % Boss print average number of hops
    receive
        {create, Node} -> % Register node
            io:format("Master initiate node:\n"),
            io:format("~w~n", [Node]), 
            io:format("Current Nodes:~n"),
            UpdatedNodes = [Node | Nodes],
            printList(UpdatedNodes),
            Node#node.pid ! {create, NumberOfRequests},
            master(NumberOfNodes, NumberOfRequests, M, UpdatedNodes);
        {join, Node} ->
            io:format("Master joining node: \n"),
            io:format("~w~n", [Node]), 
            io:format("Current Nodes:~n"),
            UpdatedNodes = [Node | Nodes],
            printList(UpdatedNodes),
            %%% find a random existing node in the network to initiate join
            Node#node.pid ! {join, lists:nth(getRandomNumber(1, length(Nodes)), Nodes), NumberOfRequests},
            master(NumberOfNodes, NumberOfRequests, M, UpdatedNodes)
    end,
    sendAllRequestsStart(NumberOfNodes, 1, Nodes).
    % masterWaitForFinish(TotalNumberOfNodes, NumberOfRequests, NumberOfHopsSoFar, NumberOfNodesLeft).

sendAllRequestsStart(_, _, []) -> ok;
sendAllRequestsStart(NumberOfNodes, CurrentIndex, [Node | Tail]) ->
    Node ! {startSendingRequests},
    sendAllRequestsStart(NumberOfNodes, CurrentIndex + 1, Tail).

createFirstNode(Master) ->
    io:format("Creating the first node~n"),
    spawn(main, nodeInit, [Master, true]).


join(Master) ->
    spawn(main, nodeInit, [Master, false]).


masterWaitForFinish(TotalNumberOfNodes, NumberOfRequests, NumberOfHopsSoFar, NumberOfNodesLeft) ->
    if
        NumberOfNodesLeft == 0 ->
            io:format("Average hops: ~w~n", [NumberOfHopsSoFar/(TotalNumberOfNodes * NumberOfRequests)]),
            io:format("Finished running program...");
        true ->
            receive
                {finito, NewNumberOfHops} -> % Node completed all required requests
                    masterWaitForFinish(TotalNumberOfNodes, NumberOfRequests, NumberOfHopsSoFar + NewNumberOfHops, NumberOfNodesLeft - 1)
            end
    end.


nodeInit(MasterNode, IsFirstNode) ->
    RandomName = getRandomString(8),
    Node = #node{id = getHash(RandomName), pid = self(), key = #key{key = RandomName, id = getHash(RandomName)}},
    case IsFirstNode of
        true ->
            master ! {create, Node};
        false ->        
            master ! {join, Node}
    end,
    
    receive

        {create, NumberOfRequests} ->
            Predecessor = Node,
            Successor = Node,
            FingerList = lists:duplicate(getM(), Node),
            io:format("Node is online:~n"),
            io:format("~w~n", [Node]),
            operate(MasterNode, NumberOfRequests, Node, Predecessor, Successor, FingerList, false, 0);
        {join, KnownNode, NumberOfRequests} ->
            Predecessor = nil,
            KnownNode#node.pid ! {findSuccessor, Node#node.key, Node},
            FingerList = lists:duplicate(getM(), KnownNode),
            receive
                {found, Key, FoundWhere, NumHops} -> % NumHops must be ignored in this case
                    io:format("Node is online:~n"),
                    io:format("~w~n", [Node]),
                    %%% node_p needs to notify node_s that it needs to change predecessor
                    FoundWhere#node.pid ! {changePredecessor, Node},
                    operate(MasterNode, NumberOfRequests, Node, Predecessor, FoundWhere, [FoundWhere], false, 0)
            end
    end.


operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops) ->
    receive
        {startSendingRequests} ->
            operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, Successor, FingerList, true, TotalNumHops);
        {whatsYourPredecessor, WhoAsked} ->
            WhoAsked#node.pid ! {predecessor, Predecessor},
            operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops);
        {whatsYourSuccessor, WhoAsked} ->
            WhoAsked#node.pid ! {successor, Successor},
            operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops);
        {findSuccessor, Key, WhoAsked} -> 
            io:fwrite("Node:\n"),
            io:fwrite("~w~n", [self()]),
            io:fwrite("receieved findSuccessor request from:\n"),
            io:fwrite("~w~n", [WhoAsked]),
            NumHops = 1,
            findSuccessor(Key, Node, FingerList, Successor, WhoAsked, NumHops),
            operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops);



        {found, Key, FoundWhere, NumHops} ->
            io:format("Node: ~p~n", [self()]),
            io:format("Key: ~p~n", [Key#key.key]),
            io:format("Key identifier: ~p~n", [Key#key.id]),
            io:format("Found at node: ~p~n", [FoundWhere#node.pid]),
            io:format("Which as identifier: ~p~n", [FoundWhere#node.id]),
            io:format("Hops: ~p~n", [NumHops]),
            operate(MasterNode, NumberOfRequestsLeft - 1, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops + NumHops);

        {notify, NewPredecessor} ->
            io:format("Node:~n"),
            io:format("~w~n", [self()]),
            io:format("Is notified of:~n"),
            io:format("~w~n", [NewPredecessor]),
            
            if
                (Predecessor == nil) or ((NewPredecessor#node.id > Node#node.id) and (NewPredecessor#node.id < Predecessor#node.id)) ->
                    operate(MasterNode, NumberOfRequestsLeft - 1, Node, NewPredecessor, Successor, FingerList, CanSendRequests, TotalNumHops);
                true ->
                    operate(MasterNode, NumberOfRequestsLeft - 1, Node, Predecessor, Successor, FingerList, CanSendRequests, TotalNumHops)
            end;
        
        {changePredecessor, NewPredecessor} ->
            io:format("Node notified changePredecessor:~n"),
            io:format("~w~n", [Node]),
            io:format("to ~w~n~n", [NewPredecessor]),
            operate(MasterNode, NumberOfRequestsLeft, Node, NewPredecessor, Successor, FingerList, CanSendRequests, TotalNumHops)

        after 1000 ->
            io:format("Node run stablize:~n"),
            io:format("~w~n", [Node]),
            NewSuccessor = stabilize(Node, Successor, Predecessor),
            NewSuccessor#node.pid ! {notify, Node},
            

            io:format("Node run Fix Finger~n"),
            if 
                Node == Successor ->
                    NewFingerList = FingerList;
                true ->
                    NewFingerList = fixFinger(FingerList, Node, Successor, getM(), 0, [])
            end,

            if
                CanSendRequests and NumberOfRequestsLeft > 0 ->
                    RandomKeyValue = getRandomString(8),
                    HashedKey = getHash(RandomKeyValue),
                    NewId = HashedKey rem round(math:pow(2, getM())),
                    NewKey = #key{id = NewId, key = RandomKeyValue},
                    findSuccessor(NewKey, Node, NewFingerList, Successor, Node, 0),
                    operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, NewSuccessor, NewFingerList, CanSendRequests, TotalNumHops);
                CanSendRequests == false ->
                    operate(MasterNode, NumberOfRequestsLeft, Node, Predecessor, NewSuccessor, NewFingerList, CanSendRequests, TotalNumHops);
                true ->
                    master ! {finito}
            end
    end.


fixFinger(_, _, _, M, M, NewList) ->
    lists:reverse(NewList);
fixFinger(FingerList, Self, KnownNode, M, I, NewList) ->
    
    Key = #key{id = Self#node.id + math:pow(2, I), key = nil},

    KnownNode#node.pid ! {findSuccessor, Key, Self},

    %io:format("VVVVVVVVVVVVV~n"),
    %io:write(Self),
    %io:write(KnownNode#node.pid),
    %io:format("~n^^^^^^^^^^^^^^^^~n"),
    receive
%        {findSuccessor, Key, WhoAsked} -> 
%            io:fwrite("Node:\n"),
%            io:fwrite("~w~n", [self()]),
%            io:fwrite("receieved findSuccessor request from:\n"),
%            io:fwrite("~w~n", [WhoAsked]),
%            NumHops = 1,
%            findSuccessor(Key, Node, FingerList, Successor, WhoAsked, NumHops)

        {found, Key, Successor, NumHops} ->

            %io:format("00000000000000000000000000000"),
            fixFinger(FingerList, Self, KnownNode, M, I + 1, [Successor | NewList])
        after 50 ->
            io:format("Fix Finger time out~n"),
            FingerList
    end.


stabilize(Self, Successor, Predecessor) ->
    if
        Self == Successor ->
            Predecessor;
        true ->
            Successor#node.pid ! {whatsYourPredecessor, Self},
            CircleSize = getCircleSize(),
            receive
                {predecessor, SuccessorPecessor} ->
                    io:format("11111111111111111111"),
                    if
                        (Successor#node.id =< Self#node.id) and (SuccessorPecessor#node.id > Self#node.id) and (SuccessorPecessor#node.id < CircleSize) ->
                            io:format("New Node detected:~n"),
                            io:format("by ~w~n", [Self]),
                            io:format("of ~w~n", [SuccessorPecessor]),
                            SuccessorPecessor;
                        
                        (SuccessorPecessor#node.id > Self#node.id) and (SuccessorPecessor#node.id < Successor#node.id) ->
                            io:format("New Node detected:~n"),
                            io:format("by ~w~n", [Self]),
                            io:format("of ~w~n", [SuccessorPecessor]),
                            SuccessorPecessor;

                        true ->
                            Successor
                    end
                after 50 ->
                    io:format("Time out~n"),
                    Successor
            end
    end.



findSuccessor(Key, Node, FingerList, Successor, WhoAsked, NumHops) ->
    %%% io:fwrite("Test\n"),
    %%% io:write(Key#key.id),
    %%% io:fwrite(" - "),
    %%% io:write(Node#node.id),
    %%% io:fwrite("\n"),
    CircleSize = getCircleSize(),
    if
        (Node#node.id == Successor#node.id) ->
            io:fwrite("Goal case1\n"),
            WhoAsked#node.pid ! {found, Key, Successor, NumHops};
        
        

        % TODO: What if successor is first node?
        %%% one potential solution is to have a upper bound of the identifier value
        %%% all hash are modded by round(math:pow(2, getM()))
        %%% if Successor.id < Node.id and node.id < key.id < round(math:pow(2, getM()))
        %%% goal! 
        
        (Node#node.id > Successor#node.id) and ((Key#key.id > Node#node.id) and (Key#key.id =< CircleSize)) ->
            io:fwrite("Goal case2\n"),
            WhoAsked#node.pid ! {found, Key, Successor, NumHops};

        (Key#key.id > Node#node.id) and (Key#key.id =< Successor#node.id) ->
            io:fwrite("Goal case3\n"),
            %%% io:fwrite("Goal\n"),
            WhoAsked#node.pid ! {found, Key, Successor, NumHops};


        true ->
            %%% io:fwrite("True case\n"),
            % TODO: replace 1 with something
            ClosestPrecedingNode = closestPrecedingNode(Key, Node, FingerList, getM(), WhoAsked),
            ClosestPrecedingNode#node.pid ! {findSuccessor, Key, WhoAsked, NumHops + 1}
    end.

closestPrecedingNode(_, Node, _, 0, WhoAsked) ->
    Node;

%%% TODO: we need to change this so that all the finger list opperations can handle successor being 1
closestPrecedingNode(Key, Node, FingerList, I, WhoAsked) ->
    io:format("LENGHT OF FINGERLIST~w~n", [length(FingerList)]),
    FingerListElement = lists:nth(I, FingerList),
    if
        (FingerListElement#node.id > Node#node.id) and (FingerListElement#node.id < Key#key.id) ->
            %%% NumHops = 1, % TODO: Fix
            %%% we only found the closest one not the final answer
            FingerListElement;
        true ->
            closestPrecedingNode(Key, Node, FingerList, I - 1, WhoAsked)
    end.