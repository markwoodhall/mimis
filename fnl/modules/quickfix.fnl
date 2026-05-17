(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {:kevinhwang91/nvim-bqf :always}))

(fn setup []
  (let [bqf (require :bqf)]
    (bqf.setup {:preview {:border nvim.o.winborder :win_height 999}})
    (fn _G.qftf [info]
      (var items nil)
      (local ret {})
      (if (= info.quickfix 1) 
        (set items
             (. (vim.fn.getqflist {:id info.id :items 0})
                :items))
        (set items (. (vim.fn.getloclist info.winid {:id info.id :items 0})
                      :items)))
      (let [limit 31
            valid-fmt "%s │%5d:%-3d│%s %s"
            fname-fmt1 (.. "%-" limit :s)
            fname-fmt2 (.. "…%." (- limit 1) :s)]
        
        (for [i info.start_idx info.end_idx]
          (local e (. items i))
          (var fname "")
          (var str nil)
          (if (= e.valid 1)
            (do
              (when (> e.bufnr 0)
                (set fname (vim.fn.bufname e.bufnr))
                (if (= fname "") (set fname "[No Name]")
                  (set fname (fname:gsub (.. "^" vim.env.HOME) "~")))
                (if (<= (length fname) limit) (set fname (fname-fmt1:format fname))
                  (set fname (fname-fmt2:format (fname:sub (- 1 limit))))))
              (let [lnum (or (and (> e.lnum 99999) (- 1)) e.lnum)
                    col (or (and (> e.col 999) (- 1)) e.col)
                    qtype (or (and (= e.type "") "")
                              (.. " " (: (e.type:sub 1 1) :upper)))]
                (set str (valid-fmt:format fname lnum col qtype e.text))))
            (set str e.text))
          (table.insert ret str)))
      ret)
    (set vim.o.qftf "{info -> v:lua._G.qftf(info)}")))

{: enable
 : setup }
