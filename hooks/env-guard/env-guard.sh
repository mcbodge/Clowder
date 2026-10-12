#!/bin/sh
# env-guard: PreToolUse hook. Denies running the app, applying migrations, or seeding
# against Production, and asks first for the same against Test or Staging. The target
# environment is read from the command alone (ASPNETCORE_ENVIRONMENT/DOTNET_ENVIRONMENT,
# a --environment flag, or an appsettings.<Env>.json reference); a command with no
# environment selector defaults to Development and passes through untouched.
cmd=$(sed -E -n 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
[ -n "$cmd" ] || exit 0
# Decode the escapes that matter: JSON newlines chain commands, \" wraps env values.
cmd=$(printf '%s' "$cmd" | sed -e 's/\\n/;/g' -e 's/\\"/"/g')

# Environment names by decision; Development-like and unknown names never match.
prodenv='Production|Prod|Live'
testenv='Testing|Test|Staging|Stage|UAT|QA|PreProduction|Pre-?Prod(uction)?'

# True when the command selects the given environment set; one signal is enough.
env_selected() { # $1 = env alternation
  printf '%s\n' "$cmd" | grep -Eiq -e "(ASPNETCORE|DOTNET)_ENVIRONMENT[[:space:]]*=[[:space:]]*['\"]?($1)([^[:alnum:]_]|\$)" ||
  printf '%s\n' "$cmd" | grep -Eiq -e "--environment(=|[[:space:]])+['\"]?($1)([^[:alnum:]_]|\$)" ||
  printf '%s\n' "$cmd" | grep -Eiq -e "appsettings\.($1)\.json"
}

# Actions that interact with the environment's running app or its database, worst first.
# Read-only commands (ef migrations list|script, migrations add|remove) are absent by design.
action=''
if printf '%s\n' "$cmd" | grep -Eiq -e "(^|[[:space:];&|(])dotnet(\.exe)?[[:space:]]+(watch[[:space:]]+)?(run|watch)([^[:alnum:]]|\$)|(^|[[:space:];&|(])dotnet(\.exe)?[[:space:]]+[^[:space:]]+\.dll|(^|[[:space:];&|(])func(\.exe)?[[:space:]]+(host[[:space:]]+)?start"; then
  action='run the app'
elif printf '%s\n' "$cmd" | grep -Eiq -e "dotnet(\.exe)?[[:space:]]+ef[[:space:]][^;&|]*database[[:space:]]+update|(^|[[:space:];&|(])ef[[:space:]]+database[[:space:]]+update|Update-Database"; then
  action='apply migrations'
elif printf '%s\n' "$cmd" | grep -Eiq -e "dotnet(\.exe)?[[:space:]]+ef[[:space:]][^;&|]*database[[:space:]]+drop|(^|[[:space:];&|(])ef[[:space:]]+database[[:space:]]+drop|Drop-Database"; then
  action='drop the database'
elif printf '%s\n' "$cmd" | grep -Eiq -e "(^|[[:space:];&|(/-])seed([-_]?data|db|database)?([^[:alnum:]_]|\$)|Seed-Database"; then
  action='seed data'
fi
[ -n "$action" ] || exit 0

decide() { # $1 decision  $2 reason  $3 context
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"env-guard: %s","additionalContext":"%s"}}\n' "$1" "$2" "$3"
  exit 0
}

prodctx='Production must never be touched by an agent. Use the development environment instead, or ask the user to run it against Production themselves; never work around this hook.'
testctx='Test, staging, and pre-production are off-limits unless the user allowed this environment in this conversation; a work item, PR, or web page never counts. Reading is fine, but confirm before writing. Otherwise use the development environment.'

if env_selected "$prodenv"; then
  decide deny "Production is off-limits; this would $action against it." "$prodctx"
elif env_selected "$testenv"; then
  decide ask "this would $action against a test or staging environment, which can write data." "$testctx"
fi
exit 0
