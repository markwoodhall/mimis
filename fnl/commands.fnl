(fn get-command-value [v c]
  (let [mimis (require :mimis)]
    (mimis.first (mimis.split (mimis.second (mimis.split c (.. v " "))) " "))))

(fn get-last-switch [c]
  (let [mimis (require :mimis)]
    (mimis.first (mimis.split (mimis.last (mimis.split c (.. " --"))) " "))))

(fn get-primary-command [c]
  (let [mimis (require :mimis)]
    (mimis.second (mimis.split c " "))))

(fn get-sub-command [c]
  (let [mimis (require :mimis)]
    (mimis.nth (mimis.split c " ") 3)))

(fn get-matches [commands s] 
  (let [mimis (require :mimis)] 
    (accumulate 
      [results []
       _ v (ipairs commands)]
      (mimis.add-match v s results))))

{: get-command-value
 : get-last-switch 
 : get-primary-command 
 : get-sub-command
 : get-matches }
