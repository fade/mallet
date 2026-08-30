;;; Control set: a binding entry is not an operator form.
;;; The first four rows fix the binding form at LET* and vary only the name; the
;;; DOLIST row varies the binding form and its value form too. The unused local
;;; function at the bottom is the only violation this file may produce.

(defun bound-labels (n)
  (let* ((c (string-downcase n))
         (labels (if (string= c "") '() (list c))))
    labels))

(defun bound-flet (n)
  (let* ((c (string-downcase n))
         (flet (if (string= c "") '() (list c))))
    flet))

(defun bound-macrolet (n)
  (let* ((c (string-downcase n))
         (macrolet (if (string= c "") '() (list c))))
    macrolet))

(defun bound-ordinary (n)
  (let* ((c (string-downcase n))
         (ordinary (if (string= c "") '() (list c))))
    ordinary))

(defun bound-in-dolist (n)
  (dolist (labels (if (string= n "") '() (list n)))
    (print labels)))

;; Known positive: a genuinely unused local function is still reported.
(defun leaves-helper-unused (n)
  (flet ((helper (x) (1+ x)))
    n))
