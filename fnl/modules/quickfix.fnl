(local nvim (require "nvim"))
(local plugins (require :plugins))

(fn enable [] 
  (plugins.register 
    {:kevinhwang91/nvim-bqf :always}))

(fn setup []
  (let [bqf (require :bqf)]
    (bqf.setup {:preview {:border nvim.o.winborder :win_height 999}})
    (local ___fn___ vim.fn)
    (fn _G.qftf [info]
      (var items nil)
      (local ret {})
      (if (= info.quickfix 1) (set items
                                   (. (___fn___.getqflist {:id info.id :items 0})
                                      :items))
        (set items (. (___fn___.getloclist info.winid {:id info.id :items 0})
                      :items)))
      (local limit 31)
      (local (fname-fmt1 fname-fmt2)
        (values (.. "%-" limit :s) (.. "…%." (- limit 1) :s)))
      (local valid-fmt "%s │%5d:%-3d│%s %s")
      (for [i info.start_idx info.end_idx]
        (local e (. items i))
        (var fname "")
        (var str nil)
        (if (= e.valid 1)
          (do
            (when (> e.bufnr 0)
              (set fname (___fn___.bufname e.bufnr))
              (if (= fname "") (set fname "[No Name]")
                (set fname (fname:gsub (.. "^" vim.env.HOME) "~")))
              (if (<= (length fname) limit) (set fname (fname-fmt1:format fname))
                (set fname (fname-fmt2:format (fname:sub (- 1 limit))))))
            (local lnum (or (and (> e.lnum 99999) (- 1)) e.lnum))
            (local col (or (and (> e.col 999) (- 1)) e.col))
            (local qtype
              (or (and (= e.type "") "")
                  (.. " " (: (e.type:sub 1 1) :upper))))
            (set str (valid-fmt:format fname lnum col qtype e.text)))
          (set str e.text))
        (table.insert ret str))
      ret)
(set vim.o.qftf "{info -> v:lua._G.qftf(info)}")))

{: enable
 : setup }
