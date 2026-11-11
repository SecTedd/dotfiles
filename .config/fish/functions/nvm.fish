# nvm in fish: runs the real (bash) nvm through foreign-env, only when called.
# env.sh already puts the default Node on PATH, so nothing is loaded at startup.
# Replaces the omf nvm package (derekstavis/plugin-nvm, MIT), which sourced
# nvm.sh in every fish start (~120 ms, also for every tmux helper command).
function nvm -d "Node version manager"
    set -q NVM_DIR; or set -gx NVM_DIR ~/.nvm
    set -l nvm_sh /opt/homebrew/opt/nvm/nvm.sh
    test -r $nvm_sh; or set nvm_sh $NVM_DIR/nvm.sh
    if not test -r $nvm_sh
        echo "nvm: nvm.sh not found (brew install nvm)" >&2
        return 1
    end
    fenv source $nvm_sh --no-use ';' nvm $argv
end
