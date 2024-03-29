% @author Mathias Brekkan and Ruiyang Li
-module(userAPI).
-include("records.hrl"). 

-export([query/1, register/0, reTweet/4, logIn/1, logOut/0, sendTweet/3, client/2, client/3, followUser/1, reg/1, followHashTag/1]).


server_node() ->
    'master@LAPTOP-M9SIRB3U'.



register() ->
    case whereis(mess_client) of % Test if the client is running
        undefined ->
            not_logged_on;
        _ ->

            mess_client ! {register},
            ok
    end.



reTweet(Message, Hashtags, Mentions, OG) ->    
    case whereis(mess_client) of % Test if the client is running
        undefined ->
            not_logged_on;
        _ -> 
            mess_client ! {sendTweet, Message, Hashtags, Mentions, OG},
            ok
    end.


printList([]) ->
    done;
printList([Head | Tail]) ->
    io:format("~s, ", [Head]),
    printList(Tail).


printQuery([]) ->
    done;
printQuery([Head | Tail]) ->
    printTweet(Head),
    printQuery(Tail).

printTweet(Tweet) ->
    io:format("~s tweeted: ~n", [Tweet#tweet.actualTweeter]),
    io:format("Originally posted by ~s~n", [Tweet#tweet.originalTweeter]),
    io:format("#"),
    printList(Tweet#tweet.hashTags),
    io:format("~n"),
    io:format("@"),
    printList(Tweet#tweet.mentions),
    io:format("~n"),           
    io:format("~s~n", [Tweet#tweet.text]).

printTweet(Username, Tweet) ->
    io:format("~s recieved: ~n", [Username]),
    io:format("~s tweeted: ~n", [Tweet#tweet.actualTweeter]),
    io:format("Originally posted by ~s~n", [Tweet#tweet.originalTweeter]),
    io:format("#"),
    printList(Tweet#tweet.hashTags),
    io:format("~n"),
    io:format("@"),
    printList(Tweet#tweet.mentions),
    io:format("~n"),           
    io:format("~s~n", [Tweet#tweet.text]).


reg(UserName) ->
    {engine, server_node()} ! {register, UserName}.


%%% User Commands
logIn(UserName) ->
    case whereis(mess_client) of
        undefined ->
            register(mess_client, spawn(userAPI, client, [server_node(), UserName]));
        _ -> 
            {engine, server_node()} ! {logIn, UserName, whereis(mess_client)}
    end.

query(UserName) ->
    case whereis(mess_client) of
        undefined ->
            register(mess_client, spawn(userAPI, client, [server_node(), UserName]));
        _ -> 
            {engine, server_node()} ! {query, UserName, whereis(mess_client)}
    end.

logOut() ->
    mess_client ! logOut.



sendTweet(Message, Hashtags, Mentions) ->
    case whereis(mess_client) of % Test if the client is running
        undefined ->
            not_logged_on;
        _ -> 
            mess_client ! {sendTweet, Message, Hashtags, Mentions},
            ok
    end.

followUser(FollowThisUsername) ->
    case whereis(mess_client) of % Test if the client is running
        undefined ->
            not_logged_on;
        _ -> 
            mess_client ! {followUser, FollowThisUsername},
            ok
    end.   

followHashTag(FollowThisHashTag) ->
    case whereis(mess_client) of % Test if the client is running
        undefined ->
            not_logged_on;
        _ -> 
            mess_client ! {followHashTag, FollowThisHashTag},
            ok
    end. 
    

%%% The client process which runs on each client node
client(Server_Node, UserName) ->

    {engine, Server_Node} ! {logIn, UserName, self()},
    io:format("login information sent~n"),
    client(Server_Node, UserName, running).

client(Server_Node, UserName, running) ->
    receive
        register ->
            {engine, Server_Node} ! {register, UserName};
        logOut ->
            {engine, Server_Node} ! {logOut, UserName},
            exit(normal);
        {sendReTweet, Message, Hashtags, Mentions, OG} ->
            Tweet = #tweet{text = Message, hashTags = Hashtags, mentions = Mentions, originalTweeter = OG, actualTweeter = UserName},
            {engine, Server_Node} ! {sendTweet, UserName, Tweet};
        {sendTweet, Message, Hashtags, Mentions} ->
            Tweet = #tweet{text = Message, hashTags = Hashtags, mentions = Mentions, originalTweeter = UserName, actualTweeter = UserName},
            {engine, Server_Node} ! {sendTweet, UserName, Tweet};
        {followUser, FollowThisUsername} ->
            {engine, Server_Node} ! {followUser, UserName, FollowThisUsername};
        {followHashTag, FollowThisHashTag} ->
            {engine, Server_Node} ! {followHashTag, UserName, FollowThisHashTag};
        {publishTweet, Tweet} ->
            printTweet(UserName, Tweet);
        {recieveQuery, Query} ->
            % Forward to sim last tweet

            printQuery(Query)
    end,
    client(Server_Node, UserName, running).