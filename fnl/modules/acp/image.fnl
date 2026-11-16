;; Images in the chat, through kitty's graphics protocol and its Unicode placeholders.
;;
;; An image is sent to the terminal once (q=2, so it never answers into Neovim's
;; input) with a virtual placement of so many columns and rows. It is then shown by
;; text: U+10EEEE in each cell, its foreground colour the image's id and diacritics its
;; row and column. Being text, the placeholders go in virtual lines that scroll, fold
;; and wrap like any other, and the terminal paints the image over them. Inside tmux
;; the escape codes are passed through (set -g allow-passthrough on), and the
;; placeholders are ordinary text to it.
;;
;; Also: Mermaid drawn as images by mmdc, themed from the colourscheme, and kept by
;; their source in the cache so a diagram is only drawn once; and other image formats
;; turned into PNG by magick, as the terminal is sent PNGs.
;;
;; vim.g.acp-images: true or false to say whether the terminal shows images, else kitty
;;   is looked for.
;; vim.g.acp-cell-size: a cell's [width height] in pixels, [9 18] if not given, for an
;;   image's size in cells; the terminal fits the image in them, keeping its shape.
;; vim.g.acp-chromium: the browser for mmdc, else chromium or google-chrome on the path.

(local diacritics
  [0x0305 0x030D 0x030E 0x0310 0x0312 0x033D 0x033E 0x033F 0x0346 0x034A 0x034B 0x034C
   0x0350 0x0351 0x0352 0x0357 0x035B 0x0363 0x0364 0x0365 0x0366 0x0367 0x0368 0x0369
   0x036A 0x036B 0x036C 0x036D 0x036E 0x036F 0x0483 0x0484 0x0485 0x0486 0x0487 0x0592
   0x0593 0x0594 0x0595 0x0597 0x0598 0x0599 0x059C 0x059D 0x059E 0x059F 0x05A0 0x05A1
   0x05A8 0x05A9 0x05AB 0x05AC 0x05AF 0x05C4 0x0610 0x0611 0x0612 0x0613 0x0614 0x0615
   0x0616 0x0617 0x0657 0x0658 0x0659 0x065A 0x065B 0x065D 0x065E 0x06D6 0x06D7 0x06D8
   0x06D9 0x06DA 0x06DB 0x06DC 0x06DF 0x06E0 0x06E1 0x06E2 0x06E4 0x06E7 0x06E8 0x06EB
   0x06EC 0x0730 0x0732 0x0733 0x0735 0x0736 0x073A 0x073D 0x073F 0x0740 0x0741 0x0743
   0x0745 0x0747 0x0749 0x074A 0x07EB 0x07EC 0x07ED 0x07EE 0x07EF 0x07F0 0x07F1 0x07F3
   0x0816 0x0817 0x0818 0x0819 0x081B 0x081C 0x081D 0x081E 0x081F 0x0820 0x0821 0x0822
   0x0823 0x0825 0x0826 0x0827 0x0829 0x082A 0x082B 0x082C 0x082D 0x0951 0x0953 0x0954
   0x0F82 0x0F83 0x0F86 0x0F87 0x135D 0x135E 0x135F 0x17DD 0x193A 0x1A17 0x1A75 0x1A76
   0x1A77 0x1A78 0x1A79 0x1A7A 0x1A7B 0x1A7C 0x1B6B 0x1B6D 0x1B6E 0x1B6F 0x1B70 0x1B71
   0x1B72 0x1B73 0x1CD0 0x1CD1 0x1CD2 0x1CDA 0x1CDB 0x1CE0 0x1DC0 0x1DC1 0x1DC3 0x1DC4
   0x1DC5 0x1DC6 0x1DC7 0x1DC8 0x1DC9 0x1DCB 0x1DCC 0x1DD1 0x1DD2 0x1DD3 0x1DD4 0x1DD5
   0x1DD6 0x1DD7 0x1DD8 0x1DD9 0x1DDA 0x1DDB 0x1DDC 0x1DDD 0x1DDE 0x1DDF 0x1DE0 0x1DE1
   0x1DE2 0x1DE3 0x1DE4 0x1DE5 0x1DE6 0x1DFE 0x20D0 0x20D1 0x20D4 0x20D5 0x20D6 0x20D7
   0x20DB 0x20DC 0x20E1 0x20E7 0x20E9 0x20F0 0x2CEF 0x2CF0 0x2CF1 0x2DE0 0x2DE1 0x2DE2
   0x2DE3 0x2DE4 0x2DE5 0x2DE6 0x2DE7 0x2DE8 0x2DE9 0x2DEA 0x2DEB 0x2DEC 0x2DED 0x2DEE
   0x2DEF 0x2DF0 0x2DF1 0x2DF2 0x2DF3 0x2DF4 0x2DF5 0x2DF6 0x2DF7 0x2DF8 0x2DF9 0x2DFA
   0x2DFB 0x2DFC 0x2DFD 0x2DFE 0x2DFF 0xA66F 0xA67C 0xA67D 0xA6F0 0xA6F1 0xA8E0 0xA8E1
   0xA8E2 0xA8E3 0xA8E4 0xA8E5 0xA8E6 0xA8E7 0xA8E8 0xA8E9 0xA8EA 0xA8EB 0xA8EC 0xA8ED
   0xA8EE 0xA8EF 0xA8F0 0xA8F1 0xAAB0 0xAAB2 0xAAB3 0xAAB7 0xAAB8 0xAABE 0xAABF 0xAAC1
   0xFE20 0xFE21 0xFE22 0xFE23 0xFE24 0xFE25 0xFE26 0x10A0F 0x10A38 0x1D185 0x1D186
   0x1D187 0x1D188 0x1D189 0x1D1AA 0x1D1AB 0x1D1AC 0x1D1AD 0x1D242 0x1D243 0x1D244])

(local placeholder (vim.fn.nr2char 0x10EEEE))
(local most (length diacritics))

(fn supported? []
  ;; The ids are 24-bit colours, so true colour is needed too.
  (and (not= vim.g.acp-images false)
       vim.o.termguicolors
       (not= nil vim.api.nvim_ui_send)
       (or (= vim.g.acp-images true)
           (not= nil vim.env.KITTY_WINDOW_ID)
           (= vim.env.TERM "xterm-kitty"))))

(fn send [control payload]
  ;; An escape code to the terminal, through tmux if it's in the way.
  (let [code (.. "\27_G" control (if payload (.. ";" payload) "") "\27\\")]
    (vim.api.nvim_ui_send
      (if vim.env.TMUX
        (.. "\27Ptmux;" (pick-values 1 (code:gsub "\27" "\27\27")) "\27\\")
        code))))

(var seeded false)

(fn new-id []
  ;; Ids are shared by everything in the terminal window, so at random, and with a
  ;; high byte, as a colour with a zero one could be taken for a 256-colour index.
  (when (not seeded)
    (math.randomseed (vim.uv.hrtime))
    (set seeded true))
  (math.random 0x100000 0xFFFFFE))

(fn png-size [path]
  ;; [width height] in pixels, from the PNG's header.
  (let [f (io.open path "rb")
        header (when f (f:read 24))]
    (when f (f:close))
    (when (and header (= 24 (length header)))
      (let [int (fn [at]
                  (let [(a b c d) (header:byte at (+ at 3))]
                    (+ (* a 16777216) (* b 65536) (* c 256) d)))]
        [(int 17) (int 21)]))))

(fn cells [size scale max-cols max-rows]
  ;; How many columns and rows an image of size pixels takes, drawn at scale, as it
  ;; would at 1 but no wider than max-cols nor, if given, taller than max-rows.
  (let [[cw ch] (or vim.g.acp-cell-size [9 18])
        [w h] size
        rows-for (fn [cols] (math.max 1 (math.min most (math.ceil (/ (* cols cw h) w ch)))))
        cols (math.max 1 (math.min (math.min max-cols most)
                                   (math.ceil (/ w scale cw))))
        rows (rows-for cols)]
    (if (and max-rows (> rows max-rows))
      (let [cols (math.max 1 (math.floor (/ (* cols max-rows) rows)))]
        (values cols (math.min max-rows (rows-for cols))))
      (values cols rows))))

(fn as-png [path callback]
  ;; Calls callback with path if it's a PNG, else with a PNG of its first frame made by
  ;; magick and kept in the cache, else with nil.
  (let [f (io.open path "rb")
        magic (when f (f:read 8))]
    (when f (f:close))
    (if (= magic "\137PNG\r\n\26\n")
      (vim.schedule #(callback path))
      (= 0 (vim.fn.executable "magick"))
      (vim.schedule #(callback nil))
      (let [stat (vim.uv.fs_stat path)
            dir (.. (vim.fn.stdpath :cache) "/acp-images")
            out (.. dir "/" (vim.fn.sha256 (.. path ":" (or (?. stat :mtime :sec) 0))) ".png")]
        (vim.fn.mkdir dir "p")
        (if (= 1 (vim.fn.filereadable out))
          (vim.schedule #(callback out))
          (let [(ok? _) (pcall vim.system ["magick" (.. path "[0]") out] {}
                               (vim.schedule_wrap
                                 #(callback (when (and (= $1.code 0) (= 1 (vim.fn.filereadable out)))
                                              out))))]
            (when (not ok?) (vim.schedule #(callback nil)))))))))

(fn place [id cols rows]
  ;; A virtual placement of cols by rows, instead of any the image had.
  (send (.. "a=d,d=i,q=2,i=" id))
  (send (.. "a=p,U=1,q=2,i=" id ",c=" cols ",r=" rows)))

(fn show [path cols rows]
  ;; Sends the PNG at path to the terminal, placed cols by rows. Returns its id.
  (let [id (new-id)]
    (send (.. "a=T,U=1,q=2,f=100,t=f,i=" id ",c=" cols ",r=" rows)
          (vim.base64.encode path))
    id))

(fn lines [id cols rows]
  ;; The placeholder text for an image, as virtual lines: every cell has its row and
  ;; column, so a partial redraw still knows where it is.
  (let [group (.. "AcpImage" id)]
    (vim.api.nvim_set_hl 0 group {:fg id})
    (fcollect [r 1 rows]
      [[(table.concat
          (fcollect [c 1 cols]
            (.. placeholder
                (vim.fn.nr2char (. diacritics r))
                (vim.fn.nr2char (. diacritics c)))))
        group]])))

;; Mermaid ----------------------------------------------------------------------------

(fn hex [n]
  (when n (string.format "#%06x" n)))

(fn theme []
  ;; mermaid's base theme in the colourscheme's colours: Catppuccin's if it's there,
  ;; else the highlight groups'.
  (let [(ok? palettes) (pcall require :catppuccin.palettes)
        (_ c) (when ok? (pcall palettes.get_palette))
        group (fn [name key] (hex (. (vim.api.nvim_get_hl 0 {: name :link false}) key)))
        text (or (?. c :text) (group :Normal :fg) "#cdd6f4")
        bg (or (?. c :base) (group :Normal :bg) "#1e1e2e")
        node (or (?. c :surface0) (group :CursorLine :bg) "#313244")
        accent (or (?. c :blue) (group :Function :fg) "#89b4fa")
        second (or (?. c :mauve) (group :Statement :fg) "#cba6f7")
        line (or (?. c :overlay1) (group :Comment :fg) "#7f849c")]
    {:theme "base"
     :themeVariables {:background bg
                      :primaryColor node
                      :primaryTextColor text
                      :primaryBorderColor accent
                      :secondaryColor node
                      :secondaryBorderColor second
                      :tertiaryColor bg
                      :tertiaryBorderColor line
                      :lineColor line
                      :textColor text
                      :mainBkg node
                      :nodeBorder accent
                      :clusterBkg bg
                      :clusterBorder line
                      :edgeLabelBackground bg
                      :titleColor text
                      :fontFamily "sans-serif"}}))

(fn browser []
  (or vim.g.acp-chromium
      (let [found (accumulate [p nil _ name (ipairs ["chromium" "google-chrome" "chromium-browser"]) &until p]
                    (let [path (vim.fn.exepath name)]
                      (when (not= path "") path)))]
        found)))

(fn mermaid? []
  (= 1 (vim.fn.executable "mmdc")))

(fn render-mermaid [source callback]
  ;; Draws source as a PNG and calls callback with its path, or with nil if mmdc
  ;; couldn't. The same source in the same colours is drawn once.
  (let [dir (.. (vim.fn.stdpath :cache) "/acp-diagrams")
        config (vim.json.encode (theme))
        key (vim.fn.sha256 (.. config "\n" source))
        out (.. dir "/" key ".png")]
    (vim.fn.mkdir dir "p")
    (if (= 1 (vim.fn.filereadable out))
      (vim.schedule #(callback out))
      (let [input (.. dir "/" key ".mmd")
            config-file (.. dir "/" key ".json")
            puppeteer (.. dir "/puppeteer.json")
            chromium (browser)]
        (vim.fn.writefile (vim.split source "\n" {:plain true}) input)
        (vim.fn.writefile [config] config-file)
        (vim.fn.writefile [(vim.json.encode (if chromium {:executablePath chromium} {}))] puppeteer)
        (let [(ok? _) (pcall vim.system
                             ["mmdc" "-q" "-i" input "-o" out "-c" config-file "-p" puppeteer
                              "-b" "transparent" "-s" "2"]
                             {}
                             (vim.schedule_wrap
                               (fn [result]
                                 (vim.fn.delete input)
                                 (vim.fn.delete config-file)
                                 (callback (when (and (= result.code 0) (= 1 (vim.fn.filereadable out)))
                                             out)))))]
          (when (not ok?) (vim.schedule #(callback nil))))))))

{: supported?
 : mermaid?
 : render-mermaid
 : png-size
 : as-png
 : cells
 : show
 : place
 : lines}
