(fn begin []
  (vim.call "plug#begin"))

(local registered {})
(fn register [plugins]
  (icollect [k v (pairs plugins)]
    (set (. registered k) v)
    ))

(fn end []
  (let [Plug (. vim.fn "plug#")]
    (icollect [k v (pairs registered)]
      (do 
        (if (not= v :always) 
          (Plug k v)
          (Plug k)))))
  (vim.call "plug#end"))

{: register
 : begin
 : end }
