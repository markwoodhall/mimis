(fn require-enable [mod args]
  (let [m (require mod)]
    (m.enable args)))

(fn require-setup [mod args]
  (let [m (require mod)]
    (m.setup args)))

(fn enable [modules]
  (icollect [k v (pairs modules)]
    (require-enable k v)))

(fn setup [modules]
  (icollect [k v (pairs modules)]
    (require-setup k v)))

{: enable
 : setup }
