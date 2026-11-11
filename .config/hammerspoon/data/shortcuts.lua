-- Shortcuts the panel can't read from the programs themselves (data only, no code).
--
-- fish: its key bindings carry no descriptions, so the useful ones are listed
--       here by hand. New fish function or binding -> one line here.
-- tmux: keys bound by plugins have no `-N` notes (ours in tmux.conf do, tmux's
--       defaults too); a plugin-bound key worth listing goes here.
--
-- key  = what the panel shows; descriptions stay short (the row has ~45 characters)
-- copy = what ⏎ puts on the clipboard for fish entries (default: the key itself);
--        abbreviations are copied without the trailing space (a paste doesn't expand them)
-- keys = what tmux receives when ⏎ runs a tmux entry
return {
  fish = {
    ours = {
      { key = "⌃X", description = "Copy the command line" },
      { key = "⌥X", description = "Copy the last command" },
      { key = "va ␣", copy = "va", description = "Expand: source the nearest .venv (then ⏎)" },
      { key = "gr ␣", copy = "gr", description = "Expand: git rup; git st; git stash list" },
      { key = "cr ␣", copy = "cr", description = "Expand: claude --resume" },
      { key = "cu ␣", copy = "cu", description = "Expand: claude update" },
      { key = "nrd ␣", copy = "nrd", description = "Expand: npm run dev" },
      { key = "rl ␣", copy = "rl", description = "Expand: exec fish (reload the config)" },
      { key = "y", copy = "y", description = "yazi; quitting cds to the last folder" },
      { key = "ask", copy = "ask", description = "Write a Claude prompt in nvim, :w sends it" },
      { key = "z <part>", copy = "z", description = "Jump to a frequent folder (zi: pick)" },
      { key = "gdf [args]", copy = "gdf", description = "Changed files + diff in fzf (⌃O edit, ⌃S add)" },
      { key = "fzfp", copy = "fzfp", description = "fzf with a bat preview of the file" },
      { key = "nvm …", copy = "nvm", description = "Node version manager" },
      { key = "lg", copy = "lg", description = "lazygit" },
      { key = "ls / ll / lt", copy = "ll", description = "eza: icons / long + git / tree" },
    },
    builtin = {
      { key = "⌃F  ⌃E", description = "Accept the autosuggestion" },
      { key = "⌥F", description = "Accept one word of the suggestion" },
      { key = "⌃R", description = "History search (fzf)" },
      { key = "⌃T", description = "Insert a file path (fzf)" },
      { key = "⌥C", description = "cd into a folder (fzf)" },
      { key = "⌥E", description = "Edit the command line in nvim" },
      { key = "⌥S", description = "Prepend sudo" },
      { key = "⌥L", description = "List the folder under the cursor" },
      { key = "⌥P", description = "Append | less" },
      { key = "⌥H", description = "Man page of the command" },
      { key = "⌥O", description = "Open the file under the cursor" },
      { key = "⌃U  ⌃K", description = "Delete to line start / end" },
      { key = "⌃W  ⌥D", description = "Delete the word before / after" },
      { key = "⌥←  ⌥→", description = "Previous / next folder (empty line)" },
      { key = "⌥↑  ⌥↓", description = "History search for the token" },
      { key = "⌃Z", description = "Undo the last edit" },
      { key = "⇥  ⇧⇥", description = "Complete / completion pager" },
      { key = "⌃L", description = "Clear screen (tmux: prefix ⌃L)" },
    },
  },
  tmux = {},
}
