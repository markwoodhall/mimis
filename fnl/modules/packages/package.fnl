(local plugins (require :plugins))
(local enabled {})

(fn require-enable [mod args]
  (when (not (. enabled mod))
    (let [m (require mod)
          deps (when m.depends (m.depends))]
      (when deps (icollect [_ v (ipairs deps)]
                   (require-enable v)))
      (m.enable args)
      (set (. enabled mod) true))))

(fn require-setup [mod args module-hook]
  (let [m (require mod)
        deps (when m.depends (m.depends))]
    (when deps (icollect [_ v (ipairs deps)]
                 (require-setup v nil mod)))
    (if module-hook 
      (m.setup args module-hook)
      (m.setup args))))

(fn enable [modules]
  (plugins.begin)
  (icollect [k v (pairs modules)]
    (do
      (require-enable k v)
      (when v.post-enable
        (v.post-enable))))
  (plugins.end))

(fn setup [modules]
  (icollect [k v (pairs modules)]
    (do 
      (require-setup k v nil)
      (when v.post-setup
        (v.post-setup)))))

{: enable
 : setup }
