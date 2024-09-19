(fn begin []
  (vim.call "plug#begin"))

(fn register [plugins]
  (let [Plug (. vim.fn "plug#")]
    (icollect [k v (pairs plugins)]
      (do 
      (if (not= v :always) 
        (Plug k v)
        (Plug k))))))

(fn end []
  (vim.call "plug#end"))

{: register
 : begin
 : end }
