(local plugins (require :plugins))

(fn require-enable [mod args module-hook]
  (let [m (require mod)
        deps (when m.depends (m.depends))]
    (when deps (icollect [_ v (ipairs deps)]
                 (require-enable v nil mod)))
    (if module-hook 
      (m.enable args module-hook)
      (m.enable args))))

(fn require-setup [mod args module-hook]
  (let [m (require mod)
        deps (when m.depends (m.depends))]
    (when deps (icollect [_ v (ipairs deps)]
                 (require-setup v nil mod)))
    (if module-hook 
      (m.setup args module-hook)
      (m.setup args))))

(fn enable [modules channel]
  (plugins.begin)
  (icollect [k v (pairs modules)]
    (do
      (require-enable k v)
      (when v.post-enable
        (v.post-enable))))
  (if channel
    (plugins.end channel)
    (plugins.end :stable)))

(fn setup [modules]
  (icollect [k v (pairs modules)]
    (do 
      (require-setup k v nil)
      (when v.post-setup
        (v.post-setup)))))

{: enable
 : setup }
