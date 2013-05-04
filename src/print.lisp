;;; print.lisp ---

;; Copyright (C) 2012, 2013 David Vazquez
;; Copyright (C) 2012 Raimon Grau

;; JSCL is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version.
;;
;; JSCL is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with JSCL.  If not, see <http://www.gnu.org/licenses/>.

;;; Printer

;;; Return T if the string S contains characters which need to be
;;; escaped to print the symbol name, NIL otherwise.
(defun escape-symbol-name-p (s &optional uppercase)
  (let ((dots-only t))
    (dotimes (i (length s))
      (let ((ch (char s i)))
        (setf dots-only (and dots-only (char= ch #\.)))
        (when (or (terminalp ch)
                  (char= ch #\:)
                  (and uppercase (not (char= ch (char (string-upcase (string ch)) 0))))
                  (char= ch #\\)
                  (char= ch #\|))
          (return-from escape-symbol-name-p t))))
    dots-only))

(defun potential-number-p (s)
  (let ((i 0)
        (n (length s))
        (ch nil))
    (flet ((next ()
                 (setf ch (and (< i n) (char s (1- (incf i)))))))
      (next)
      (cond
       ((null ch) (return-from potential-number-p))
       ((digit-char-p ch))
       ((char= ch #\.))
       ((char= ch #\+) (next))
       ((char= ch #\-) (next))
       (t (return-from potential-number-p)))
      (when ch
        (while (and ch (digit-char-p ch)) (next))
        (when (null ch)
          (return-from potential-number-p t)))
      (when (char= ch #\.)
        (next)
        (when ch
          (while (and ch (digit-char-p ch)) (next))))
      (when (or (char= ch #\E) (char= ch #\e)
                (char= ch #\D) (char= ch #\d)
                (char= ch #\F) (char= ch #\f)
                (char= ch #\L) (char= ch #\l))
        (next)
        (cond
         ((null ch) (return-from potential-number-p))
         ((digit-char-p ch))
         ((char= ch #\+) (next))
         ((char= ch #\-) (next))
         (t (return-from potential-number-p)))
        (unless (and ch (digit-char-p ch))
          (return-from potential-number-p))
        (while (and ch (digit-char-p ch)) (next)))
      (null ch))))

(defun escape-token-p (string &optional uppercase)
  (or (potential-number-p string)
      (escape-symbol-name-p string uppercase)))

(defun escape-token (s &optional uppercase)
  (if (escape-token-p s uppercase)
      (let ((result "|"))
        (dotimes (i (length s))
          (let ((ch (char s i)))
            (when (or (char= ch #\|)
                      (char= ch #\\))
              (setf result (concat result "\\")))
            (setf result (concat result (string ch)))))
        (concat result "|"))
      s))


(defvar *print-escape* t)

(defun write-to-string (form)
  (cond
    ((null form) "NIL")
    ((symbolp form)
     (let ((name (symbol-name form))
           (package (symbol-package form)))
       (if (eq package *package*)
           (escape-token (symbol-name form) (not (eq package *js-package*)))
           (concat (cond
                     ((null package) "#")
                     ((eq package (find-package "KEYWORD")) "")
                     (t (escape-token (package-name package) t)))
                   ":"
                   (if (or (null package)
                           (multiple-value-bind (_ status)
                               (find-symbol name package)
                             (eq status :external)))
                       "" ":")
                   (escape-token name (not (eq (symbol-package form) *js-package*)))))))
    ((integerp form) (integer-to-string form))
    ((floatp form) (float-to-string form))
    ((characterp form)
     (concat "#\\"
             (case form
               (#\newline "newline")
               (#\space "space")
               (otherwise (string form)))))
    ((stringp form) (if *print-escape*
                        (concat "\"" (escape-string form) "\"")
                        form))
    ((functionp form)
     (let ((name (oget form "fname")))
       (if name
           (concat "#<FUNCTION " name ">")
           (concat "#<FUNCTION>"))))
    ((listp form)
     (concat "("
             (join-trailing (mapcar #'write-to-string (butlast form)) " ")
             (let ((last (last form)))
               (if (null (cdr last))
                   (write-to-string (car last))
                   (concat (write-to-string (car last)) " . " (write-to-string (cdr last)))))
             ")"))
    ((arrayp form)
     (concat "#" (if (zerop (length form))
                     "()"
                     (write-to-string (vector-to-list form)))))
    ((packagep form)
     (concat "#<PACKAGE " (package-name form) ">"))
    (t
     (concat "#<javascript object>"))))

(defun prin1-to-string (form)
  (let ((*print-escape* t))
    (write-to-string form)))

(defun princ-to-string (form)
  (let ((*print-escape* nil))
    (write-to-string form)))

(defun write-line (x)
  (write-string x)
  (write-string *newline*)
  x)

(defun warn (string)
  (write-string "WARNING: ")
  (write-line string))

(defun print (x)
  (write-line (prin1-to-string x))
  x)

(defun format (destination fmt &rest args)
  (let ((len (length fmt))
        (i 0)
        (res "")
        (arguments args))
    (while (< i len)
      (let ((c (char fmt i)))
        (if (char= c #\~)
            (let ((next (char fmt (incf i))))
              (cond
               ((char= next #\~)
                (concatf res "~"))
               ((char= next #\%)
                (concatf res *newline*))
               (t
                (concatf res (format-special next (car arguments)))
                (pop arguments))))
            (setq res (concat res (char-to-string c))))
        (incf i)))
    (if destination
        (progn
          (write-string res)
          nil)
        res)))

(defun format-special (chr arg)
  (case chr
    (#\S (prin1-to-string arg))
    (#\a (princ-to-string arg))))
