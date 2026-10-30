;; Elicitation form mode: the fields of an agent's question, asked through
;; vim.ui.select and vim.ui.input (so adapters and tests can stand in), then a
;; review where every answer can be changed before anything is submitted.
;;
;; ask asks the fields in their given order, then the review. done gets
;; :accept with the answers for the agent's content field, or :decline, or
;; :cancel when a prompt was dismissed without choosing.

(fn value-label [field value]
  ;; An answer for the review list, abbreviated to one line.
  (if (= nil value) ""
      (= field.kind :boolean) (if value "yes" "no")
      (let [name (accumulate [hit nil _ o (ipairs (or field.values [])) &until hit]
                   (when (= o.value value) o.name))]
        (pick-values 1 (string.gsub (or name (tostring value)) "\n" " ")))))

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
                    (vim.ui.input
                      {:prompt (.. field.name
                                   (if (= kind :number) " (number)" "")
                                   ": ")
                       :default (or (and (not= current nil) (tostring current))
                                    (and (not= nil (?. field :default))
                                         (tostring field.default)))}
                      #(give kind $1)))]
    (case field.kind
      :choice (vim.ui.select field.values
                {:prompt (.. field.name ": ")
                 :format_item (fn [o]
                                (.. (if (= current o.value) "* " "  ")
                                    o.name
                                    (if o.description (.. " — " o.description) "")))}
                (fn [o]
                  (if o (answered o.value) (done :cancel))))
      :boolean (vim.ui.select [{:value true :name "yes"} {:value false :name "no"}]
                 {:prompt (.. field.name ": ")
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
                 :label (.. f.name ": " (value-label f (. answers f.name)) " — edit")})]
    (table.insert items {:kind :submit :label "Submit"})
    (table.insert items {:kind :decline :label "Decline without answering"})
    (vim.ui.select items
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
