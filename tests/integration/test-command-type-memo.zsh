#!/usr/bin/env zsh

# Command types are memoized for the line being edited: a new command line or
# a change of directory resolves them again, and a function definition typed
# on the line never outlives the pass that saw it.

emulate -R zsh
setopt err_exit no_unset no_function_argzero posix_argzero

typeset -r plugin_root=${${(%):-%N}:A:h:h:h}
typeset -r fixture_root=$(command mktemp -d "${TMPDIR:-/tmp}/fsyh-type-memo.XXXXXXXX")
trap 'command rm -rf -- "$fixture_root"' EXIT HUP INT TERM

typeset -gx ZDOTDIR=$fixture_root/zdotdir
typeset -gx XDG_CACHE_HOME=$fixture_root/cache-home
command mkdir -p -- "$ZDOTDIR" "$fixture_root/a/probe-dir" "$fixture_root/b"
zstyle ':fsh:config' work-dir "$fixture_root/work"

source "$plugin_root/F-Sy-H.plugin.zsh"
fpath=( "$plugin_root"/{functions,completions,chroma} \
  "${(@)fpath:#$plugin_root/(functions|completions|chroma)}" )
# Loading without a terminal skips the hook; install it as an interactive
# load does, since the memo only lives while the hook can clear it.
typeset -ga preexec_functions=( _fsh_preexec_hook )

typeset BUFFER= PREBUFFER= WIDGET=self-insert
integer CURSOR=0 REGION_ACTIVE=0
typeset -a region_highlight

_fsh_test_highlight() {
  BUFFER=$1 CURSOR=$#1
  _fsh_zle_highlight
}

# Zsh runs preexec hooks before every top-level command of a script too, so
# each line-editing session below is one top-level command.
builtin cd -- "$fixture_root/a"

# Resolved once, then served from the memo for the rest of the line.
{
  _fsh_test_highlight 'fsh_memo_probe arg'
  [[ ${_fsh_command_type_memo[fsh_memo_probe]-} == none ]]
  _fsh_command_type_memo[fsh_memo_probe]=sentinel
  _fsh_test_highlight 'fsh_memo_probe arg2'
  [[ ${_fsh_command_type_cache[fsh_memo_probe]-} == sentinel ]]
}

# A new command line resolves again.
fsh_memo_probe() { :; }
{
  _fsh_test_highlight 'fsh_memo_probe arg'
  [[ ${_fsh_command_type_memo[fsh_memo_probe]-} == function ]]
}

# A definition typed on the line applies to that pass only.
{
  _fsh_test_highlight 'ls() { :; }'
  [[ ${_fsh_command_type_memo[ls]-} != function ]]
  _fsh_test_highlight 'ls -l'
  [[ ${_fsh_command_type_cache[ls]-} == ${_fsh_command_type_memo[ls]-} ]]
  [[ ${_fsh_command_type_cache[ls]-} != function ]]
}

# Relative directories depend on the working directory.
{
  _fsh_test_highlight 'probe-dir'
  [[ ${_fsh_command_type_memo[probe-dir]-} == dirpath ]]
  builtin cd -- "$fixture_root/b"
  _fsh_test_highlight 'probe-dir '
  [[ ${_fsh_command_type_memo[probe-dir]-} == none ]]
}

# Without the hook nothing ends a command line, so nothing is memoized
# across passes.
preexec_functions=()
{
  _fsh_test_highlight 'fsh_memo_probe arg'
  _fsh_command_type_memo[fsh_memo_probe]=sentinel
  _fsh_test_highlight 'fsh_memo_probe arg2'
  [[ ${_fsh_command_type_cache[fsh_memo_probe]-} == function ]]
}

fsh_plugin_unload
