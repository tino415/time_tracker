;; Time Tracker
;; :PROPERTIES:
;; :repo-path: ~/Projects/tino415/time_tracker
;; :header-args+: :dir (org-entry-get nil "repo-path" t)
;; :END:

;; Offline-first Flutter time-activity tracker (continuous change-point tracking):
;; Android phone + Wear OS watch + web PWA. Sibling of Gym Tracker — same
;; platform/nix machinery. Sync backend deferred (each client standalone on local
;; Drift; CSV export client-side). See ~/org/todo.org "Time-activity tracking app".

;; #+header: :tangle (concat (org-entry-get nil "repo-path" t) "/.dir-locals.el")
;; #+header: :comments both

;; [[file:../../../org/repositories.org::*Time Tracker][Time Tracker:1]]
;;; Directory Local Variables            -*- no-byte-compile: t -*-
;;; For more information see (info "(emacs) Directory Variables")

((nil . ((project-up-command . "nx just up")
         (project-install-command . "nx just deploy"))))
;; Time Tracker:1 ends here
