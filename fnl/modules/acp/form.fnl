;; Elicitation form mode: the fields of an agent's question, asked through
;; ui.select and ui.input (floating windows, or a replaced vim.ui so adapters and
;; tests can stand in), then a review where every answer can be changed before
;; anything is submitted.
;;
;; ask asks the fields in their given order, then the review. done gets
;; :accept with the answers for the agent's content field, or :decline, or
;; :cancel when a prompt was dismissed without choosing.

(local ui (require :modules.acp.ui))

(fn prompt-of [field]
  ;; What a field asks: its title and description when it has them, else its name.
  (let [parts (icollect [_ p (ipairs [field.title field.description])]
                (when (and p (not= p "")) p))]
    (.. (if (> (length parts) 0) (table.concat parts " — ") field.name) ": ")))

(fn label-of [field]
  ;; A field as the review list names it: short, one line.
  (let [text (pick-values 1 (string.gsub (or field.title field.description field.name) "%s*\n%s*" " "))]
    (if (> (vim.fn.strchars text) 50)
      (.. (vim.fn.strcharpart text 0 49) "…")
      text)))

(fn name-of [field value]
  (let [name (accumulate [hit nil _ o (ipairs (or field.values [])) &until hit]
               (when (= o.value value) o.name))]
    (pick-values 1 (string.gsub (or name (tostring value)) "\n" " "))))

(fn value-label [field value]
  ;; An answer for the review list, abbreviated to one line.
  (if (= nil value) ""
      (= field.kind :boolean) (if value "yes" "no")
      (= field.kind :multichoice)
      (table.concat (icollect [_ v (ipairs value)] (name-of field v)) ", ")
      (name-of field value)))

(fn content [fields answers]
  ;; The body for an accepted reply: every answered field, optional ones left
  ;; empty only absent. An empty dict, never an empty array.
  (let [c (vim.empty_dict)]
    (each [_ f (ipairs fields)]
      (let [v (. answers f.name)]
        (when (not= v nil)
          (tset c f.name v))))
    c))

(fn ask-field [field answers done continue]
  ;; Answers one field, then continues the walk. Leaving through the input line
  ;; answers nil: kept as no answer for optional fields, refused for required
  ;; ones, so an answer can always be given. Cancel means done with the form.
  (let [current (. answers field.name)
        answered (fn [value]
                   (tset answers field.name value)
                   (continue))
        retry (fn [why]
                (vim.notify (.. "acp: " why) vim.log.levels.WARN)
                (ask-field field answers done continue))
        give (fn [kind text]
               (if (= nil text)
                 (done :cancel)
                 (let [text (vim.trim text)]
                   (if (= "" text)
                     (if field.required?
                       (retry (.. field.name " is required"))
                       (answered nil))
                     (= kind :number)
                     (let [value (tonumber text)]
                       (if (not value)
                         (retry (.. field.name " needs a number"))
                         (and field.minimum (< value field.minimum))
                         (retry (.. field.name " is at least " (tostring field.minimum)))
                         (and field.maximum (> value field.maximum))
                         (retry (.. field.name " is at most " (tostring field.maximum)))
                         (answered value)))
                     (answered text)))))
        ask-input (fn [kind]
                    (ui.input
                      {:prompt (.. (prompt-of field)
                                   (if (= kind :number) " (number)" ""))
                       :default (or (and (not= current nil) (tostring current))
                                    (and (not= nil (?. field :default))
                                         (tostring field.default)))}
                      #(give kind $1)))]
    (fn ask-multi []
      ;; Choosing an option toggles it and asks again, so any number can be ticked;
      ;; "Done" settles the answer. Dismissing the picker cancels the whole form.
      (let [chosen (vim.list_slice (or current (and (= :table (type field.default)) field.default) []))
            has? (fn [v] (vim.tbl_contains chosen v))
            lo (or field.min-items (if field.required? 1 0))
            hi field.max-items]
        (fn pick [cursor]
          (let [items (vim.list_slice field.values)]
            (table.insert items {:done true :name "Done"})
            (ui.select items
              {:prompt (prompt-of field)
               :cursor cursor
               :format_item (fn [o]
                              (if o.done
                                (.. "  " o.name " (" (length chosen) " chosen)")
                                (.. (if (has? o.value) "[x] " "[ ] ")
                                    o.name
                                    (if o.description (.. " — " o.description) ""))))}
              (fn [o i]
                (if (not o) (done :cancel)
                    (not o.done)
                    (do (let [at (accumulate [hit nil j v (ipairs chosen) &until hit]
                                               (when (= v o.value) j))]
                          (if at (table.remove chosen at) (table.insert chosen o.value)))
                        (pick i))
                    (< (length chosen) lo)
                    (do (vim.notify (.. "acp: " field.name " needs at least " lo " chosen")
                                    vim.log.levels.WARN)
                        (pick i))
                    (and hi (> (length chosen) hi))
                    (do (vim.notify (.. "acp: " field.name " takes at most " hi)
                                    vim.log.levels.WARN)
                        (pick i))
                    (answered (if (= 0 (length chosen)) nil chosen)))))))
        (pick 1)))
    (case field.kind
      :choice (let [items (vim.list_slice field.values)]
                ;; Leaving an optional question unanswered is a choice too: dismissing
                ;; the picker cancels the whole form.
                (when (not field.required?)
                  (table.insert items {:skip true :name "(skip)"}))
                (ui.select items
                  {:prompt (prompt-of field)
                   :format_item (fn [o]
                                  (.. (if (and (not o.skip) (= current o.value)) "* " "  ")
                                      o.name
                                      (if o.description (.. " — " o.description) "")))}
                  (fn [o]
                    (if (not o) (done :cancel)
                        o.skip (answered nil)
                        (answered o.value)))))
      :multichoice (ask-multi)
      :boolean (ui.select [{:value true :name "yes"} {:value false :name "no"}]
                 {:prompt (prompt-of field)
                  :format_item (fn [o]
                                 (.. (if (= current o.value) "* " "  ") o.name))}
                 (fn [o]
                   (if o (answered o.value) (done :cancel))))
      :number (ask-input :number)
      :string (ask-input :string)
      _ (done :decline))))

(fn review [fields answers done]
  ;; Nothing is sent before the answers have been shown and the user agreed or
  ;; changed them. Editing a field returns here; decline is always offered.
  (let [items (icollect [_ f (ipairs fields)]
                {:kind :edit :field f
                 :label (.. (label-of f) ": " (value-label f (. answers f.name)) " — edit")})]
    (table.insert items {:kind :submit :label "Submit"})
    (table.insert items {:kind :decline :label "Decline without answering"})
    (ui.select items
                   {:prompt "Answers: "
                    :format_item #(. $1 :label)}
                   (fn [item]
                     (if (not item)
                       (done :cancel)
                       (= item.kind :submit)
                       (done :accept (content fields answers))
                       (= item.kind :decline)
                       (done :decline)
                       (ask-field item.field answers done
                                  #(review fields answers done)))))))

(fn ask [fields done]
  ;; The walk over a form's fields: ask-field until they run out, then review.
  (fn next-field [i answers]
    (let [field (. fields i)]
      (if field
        (ask-field field answers done #(next-field (+ i 1) answers))
        (review fields answers done))))
  (next-field 1 {}))

{: ask}
