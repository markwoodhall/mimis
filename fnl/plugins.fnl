(fn begin []
  (vim.call "plug#begin"))

(local registered {})
(fn register [plugins]
  (icollect [k v (pairs plugins)]
    (set (. registered k) v)
    ))

(fn end [channel]
  (let [Plug (. vim.fn "plug#")
        lock (require :packagelock)]
    (icollect [k v (pairs registered)]
      (do 
        (let [p-lock (. lock channel k)]
          (if (not= v :always) 
              (do (when p-lock
                (set (. v :commit) p-lock))
                (Plug k v))
              (if p-lock
                  (Plug k {:commit p-lock})
                  (Plug k)))))))
  (vim.call "plug#end"))

(vim.api.nvim_create_user_command
             "MimisInstall"
             (fn [_]
               (vim.cmd "PlugInstall")
               (vim.cmd "helptags ~/.config/nvim/doc"))
             {:bang false :desc "Init mimis" :nargs "*"})

(vim.api.nvim_create_user_command
             "MimisUpdate"
             (fn [_]
               (vim.cmd "PlugUpgrade")
               (vim.cmd "PlugUpdate!")
               (vim.cmd "helptags doc"))
             {:bang false :desc "Install mimis" :nargs "*"})

{: register
 : begin
 : end }
