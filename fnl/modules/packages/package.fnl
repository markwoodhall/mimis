(local plugins (require :plugins))

(fn require-enable [mod args]
  (let [m (require mod)]
    (m.enable args)))

(fn require-setup [mod args]
  (let [m (require mod)]
    (m.setup args)))

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
      (require-setup k v)
      (when v.post-setup
        (v.post-setup)))))

{: enable
 : setup }