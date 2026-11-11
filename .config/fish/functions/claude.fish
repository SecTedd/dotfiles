# Claude Code with this Mac's plugins. Claude Code has no user-level local
# settings file, so the plugins and marketplaces of this Mac live in
# ~/.claude/plugins.local.json (git-ignored, template in templates/claude/) and
# are passed with --settings on every start. Without the file: plain claude.
function claude --wraps claude -d "Claude Code (+ ~/.claude/plugins.local.json)"
    set -l local_settings ~/.claude/plugins.local.json
    if test -r $local_settings
        command claude --settings $local_settings $argv
    else
        command claude $argv
    end
end
