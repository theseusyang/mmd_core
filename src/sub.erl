%% Copyright 2012 PEAK6 Investments, L.P.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%%-------------------------------------------------------------------
%%% @author sparish@peak6.com
%%% @copyright (C) 2012, PEAK6 Investments, L.P.
%%% @doc
%%%
%%% @end
%%% Created : Thr May 03 08:42:59 CDT 2011
%%%-------------------------------------------------------------------
-module(sub).

-export([start_link/0]).
-export([xformEntryAdd/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-include_lib("p6core/include/logger.hrl").
-include("mmd.hrl").
-include_lib("p6core/include/dmap.hrl").

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    gen_server:start_link({local, sub}, ?MODULE, [], []).

xformEntryAdd(E) -> E.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
init([]) ->
    p6dmap:new(subs, ?MODULE),
    services:regLocal(sub),
    {ok, channel_mgr:new()}.

handle_call({mmd, From, Msg}, _From, Chans) ->
    {reply, ok,
     case channel_mgr:process_remote(Chans, From, Msg) of
         {NewChans, CC=#channel_create{type=call}} ->
             R = channel_mgr:process_local(
                   NewChans,
                   mmd_msg:mkError(CC,
                                   ?INVALID_REQUEST,
                                   <<"'sub' doesn't support Call channels">>)),
             case R of
                 {NewChans2, []} -> NewChans2;
                 {NewChans2, Other} ->
                     ?linfo("Dunno what to do with: ~p",[Other]),
                     NewChans2
             end;
         {NewChans, CC=#channel_create{type=sub, body=Raw, id=ChanId}} ->
             case mmd_decode:decode(Raw) of
                 {?array(Topics), _} ->
                     add_topics(From, ChanId, Topics, CC, NewChans);
                 {<<Topic/binary>>, _} ->
                     add_topics(From, ChanId, [Topic], CC, NewChans);
                 _ ->
                     bad_sub(CC, NewChans)
             end;
         {NewChans, CM=#channel_message{}} ->
             {Chans2, _M} =
                 channel_mgr:process_local(
                   NewChans,
                   mmd_msg:mkError(CM,
                                   ?INVALID_REQUEST,
                                   <<"'sub' doesn't accept channel message">>)),
             Chans2;
         {NewChans, #channel_close{}} ->
             NewChans
     end};
handle_call(Request, From, State) ->
    ?lwarn("Unexpected handle_call(~p, ~p, ~p)",[Request,From,State]),
    {reply, ok, State}.

handle_cast({pub, Msg}, Chans) ->
    channel_mgr:sendAll(Chans, Msg),
    {noreply, Chans};
handle_cast(Msg, State) ->
    ?lwarn("Unexpected handle_cast(~p, ~p)",[Msg,State]),
    {noreply, State}.

handle_info(Info, State) ->
    ?lwarn("Unexpected handle_info(~p, ~p)",[Info, State]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

add_topics(_From, _ChanId, [], _CC, Chans) -> Chans;
add_topics(From, ChanId, [<<T/binary>> | Topics], CC, Chans) ->
    p6dmap:addGlobal(subs, From, T, {self(), ChanId}),
    add_topics(From, ChanId, Topics, CC, Chans);
add_topics(_From, _ChanId, _Topics, CC, Chans) ->
    bad_sub(CC, Chans).

bad_sub(CC, Chans) ->
    {Chans2, _M} =
        channel_mgr:process_local(
          Chans,
          mmd_msg:mkError(CC,
                          ?INVALID_REQUEST,
                          <<"'sub' must be initiated with a string or list "
                            "of strings of topics to subscribe to">>)),
    Chans2.