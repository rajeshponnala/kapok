%% Compiler for kapok
-module(kapok_compiler).
-export([file/1,
         string/2,
         string_to_ast/4,
         'string_to_ast!'/4,
         eval/2,
         eval/3,
         eval_ast/2,
         eval_ast/3]).
-export([core/0]).
-import(kapok_utils, [to_binary/1]).
-include("kapok.hrl").

%% Public API

%% Compilation entry points.

file(File) when is_binary(File)->
  {ok, Bin} = file:read_file(File),
  Contents = kapok_utils:characters_to_list(Bin),
  string(Contents, File).

string(String, File) ->
  Ast = 'string_to_ast!'(String, 1, File, []),
  Ctx = kapok_ctx:ctx_for_eval([{line, 1}, {file, File}]),
  kapok_ast:compile(Ast, Ctx).

%% Convertion

%% Converts a given string (char list) into AST.
string_to_ast(String, StartLine, File, Options) when is_integer(StartLine), is_binary(File) ->
  case kapok_scanner:scan(String, StartLine, [{file, File}|Options]) of
    {ok, Tokens, _EndLocation} ->
      try kapok_parser:parse(Tokens) of
          {ok, Forms} -> {ok, Forms};
          {error, {_Line, _Module, _ErrorDescription}} = E -> E
      catch
        {error, {_Line, _Module, _ErrorDescription}} = E -> E
      end;
    {error, {Location, Module, ErrorDescription}, _Rest, _SoFar} ->
      {Line, _} = Location,
      {error, {Line, Module, ErrorDescription}}
  end.

'string_to_ast!'(String, StartLine, File, Options) ->
  case string_to_ast(String, StartLine, File, Options) of
    {ok, Forms} ->
      Forms;
    {error, {Line, Module, ErrorDesc}} ->
      kapok_error:parse_error(Line, File, Module, ErrorDesc)
  end.


%% Converts AST to erlang abstract format
ast_to_abstract_format(Ast, Ctx) ->
  kapok_trans:translate(Ast, Ctx).

%% Evaluation

%% String Evaluation
eval(String, Bindings) ->
  eval(String, Bindings, []).

eval(String, Bindings, Options) when is_list(Options) ->
  eval(String, Bindings, kapok_ctx:ctx_for_eval(Options));
eval(String, Bindings, #{line := Line, file := File} = Ctx)
    when is_list(String), is_list(Bindings), is_integer(Line), is_binary(File) ->
  Ast = 'string_to_ast!'(String, Line, File, []),
  eval_ast(Ast, Bindings, Ctx).

%% AST Evaluation
eval_ast(Ast, Bindings, Options) when is_list(Options) ->
  eval_ast(Ast, Bindings, kapok_ctx:ctx_for_eval(Options));
eval_ast(Ast, Bindings, Ctx) ->
  {_, Ctx1} = kapok_ctx:add_bindings(Ctx, Bindings),
  eval_ast(Ast, Ctx1).
eval_ast(Ast, Ctx) ->
  {Forms, TCtx1} = ast_to_abstract_format(Ast, Ctx),
  kapok_erl:eval_abstract_format(Forms, TCtx1).

%% CORE HANDLING

core() ->
  compile_libs([{core, true}], fun core_libs/0).

compile_libs(Options, Fun) ->
  {ok, _} = application:ensure_all_started(kapok),
  AllOptions = orddict:merge(fun (_K, V1, _V2) -> V1 end,
                             orddict:from_list(Options),
                             orddict:from_list([{docs, false}])),
  kapok_env:update_in(compiler_options, AllOptions),
  lists:foreach(fun (F) -> load_lib(list_to_binary(F)) end, Fun()).

load_lib(File) ->
  InDir = "lib/kapok/lib",
  OutDir = <<"lib/kapok/ebin">>,
  kapok_env:put(outdir, OutDir),
  F = list_to_binary(filename:join(InDir, binary_to_list(File))),
  try
    io:format("Compile '~s'~n", [F]),
    _Ctx = file(F)
  catch
    Kind:Reason ->
      io:format("~p: ~p~nstacktrace: ~p~n", [Kind, Reason, erlang:get_stacktrace()]),
      erlang:halt(1)
  end.

core_libs() ->
  ["kapok.core.kpk",
   "kapok.module.kpk",
   "kapok.code-server.kpk",
   "kapok.protocol.kpk"
  ].
