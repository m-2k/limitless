%%% @author Leonardo Rossi <leonardo.rossi@studenti.unipr.it>
%%% @copyright (C) 2016 Leonardo Rossi
%%%
%%% This software is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This software is distributed in the hope that it will be useful, but
%%% WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this software; if not, write to the Free Software Foundation,
%%% Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
%%%
%%% @doc limitless public API
%%% @end

-module(limitless).

-author('Leonardo Rossi <leonardo.rossi@studenti.unipr.it>').

-export([
  init/0,
  is_reached/2,
  is_reached_multiple/2,
  setup/3
]).

%% Types

-type appctx()       :: #{ctx => ctx(), limits => list()}.
-type ctx()          :: limitless_backend:ctx().
-type limit()        :: limitless_backend:limit().
-type limit_extra()  :: {boolean(), objectid(), limits_info()}.
-type limits_extra() :: list(limit_extra()).
-type limits_info()  :: limitless_backend:limits_info().
-type objectid()     :: limitless_backend:objectid().


%%====================================================================
%% API
%%====================================================================

-spec init() -> {ok, appctx()}.
init() ->
  {ok, BackendConfig} = application:get_env(limitless, backend),
  {ok, Ctx} = limitless_backend:init(BackendConfig),
  {ok, set_limits(application:get_env(limitless, limits), #{ctx => Ctx})}.

-spec is_reached(list(objectid()), appctx()) ->
    {boolean(), objectid() | notfound, limits_extra()}.
% @doc consume the first objectid available.
% @end
is_reached(ObjectIds, #{ctx := Ctx}=AppCtx) ->
  InfoObjects = get_consumables(ObjectIds, AppCtx),
  {IsReached, ObjectId} = consume(lists:keyfind(false, 1, InfoObjects), Ctx),
  {IsReached, ObjectId, InfoObjects}.

-spec is_reached_multiple(list(objectid()), appctx()) ->
  {boolean(), list({objectid(), limits_extra()})}.
% @doc consume the every objectids available.
% @end
is_reached_multiple(ObjectIds, #{ctx := Ctx}=AppCtx) ->
  InfoObjects = get_consumables(ObjectIds, AppCtx),
  ConsumedIds = lists:filtermap(
    fun({false, ObjectId, _}) ->
        limitless_backend:dec(ObjectId, Ctx),
        {true, ObjectId};
       (_) -> false
    end, InfoObjects),
  IsReached = ConsumedIds == [],
  {IsReached, ConsumedIds, InfoObjects}.

% @doc Setup limmits from configuration: initialize in database.
% @end
-spec setup(objectid(), atom(), appctx()) ->
    list({ok, limit()} | {error, term()}).
setup(ObjectId, Group, #{ctx := Ctx, limits := LimitsConfig}) ->
  PrefixId = prefix_id(ObjectId, Group),
  lists:map(fun(Config) ->
      Type = limitless_utils:get_or_fail(type, Config),
      Frequency = limitless_utils:get_or_fail(frequency, Config),
      Requests = limitless_utils:get_or_fail(requests, Config),
      Id = << PrefixId/binary, Type/binary >>,
      limitless_backend:create(
        Type, Id, ObjectId, Frequency, Requests, Ctx)
    end, proplists:get_value(Group, LimitsConfig)).

%%====================================================================
%% Internal functions
%%====================================================================

-spec prefix_id(objectid(), atom()) -> binary().
prefix_id(ObjectId, Group) ->
  GroupBinary = list_to_binary(atom_to_list(Group)),
  << ObjectId/binary, <<"_">>/binary, GroupBinary/binary, <<"_">>/binary >>.

-spec get_consumables(list(objectid()), appctx()) ->
    list({boolean(), objectid(), limits_info()}).
get_consumables(ObjectIds, #{ctx := Ctx}) ->
  lists:map(fun(ObjectId) ->
      % reset limits
      limitless_backend:reset_expired(ObjectId, Ctx),
      % check if limit is reached
      {Reached, Limits} = limitless_backend:is_reached(ObjectId, Ctx),
      ExtraInfo = limitless_backend:extra_info(Limits),
      {Reached, ObjectId, ExtraInfo}
    end, ObjectIds).

-spec consume({false, objectid(), any()} | false, ctx()) ->
    {boolean(), objectid() | notfound}.
consume(false, _) -> {true, notfound};
consume({false, ObjectId, _}, Ctx) ->
  limitless_backend:dec(ObjectId, Ctx),
  {false, ObjectId}.

-spec set_limits(undefined | {ok, list()}, appctx()) -> appctx().
set_limits(undefined, AppCtx) -> AppCtx;
set_limits({ok, LimitsConfig}, AppCtx) -> AppCtx#{limits => LimitsConfig}.
