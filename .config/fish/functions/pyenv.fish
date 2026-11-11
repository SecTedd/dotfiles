# pyenv in fish: `pyenv init` (rehash, completions, the shell wrapper for
# `pyenv shell`) is loaded on first use, like nvm.fish does for nvm. env.sh
# already puts the shims on PATH, so nothing is loaded at startup.
function pyenv -d "Python version manager"
    functions -e pyenv
    command pyenv init - --no-rehash fish | source
    pyenv $argv
end
