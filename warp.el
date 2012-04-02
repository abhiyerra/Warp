;;;warp.el --- Web Applications Realtime Preview Minor Mode
;; -*- Mode: Emacs-Lisp -*-

;; Copyright (C) 2012 by yukihr

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA

;;;Version: 0.0.1
;; Author: yukihr (Yukihiro Hara), <yukihr [at] gmail [dot] com>
;; URL: http://yukihr.github.com/

;;;Contributers

;;;Installation
;; Put this file into load-path'ed directory, and byte compile it if
;; desired. And put the following expression into your ~/.emacs.
;;
;; (require 'warp)
;;
;; If you use default key map, Put the following expression into your ~/.emacs.
;;
;; ;;; (warp-set-default-keymap)

;;; Commentary:

;;; Commands:

;;; TODO
;;  * Stuck when large buffer is sent

;;; Code:

(require 'easy-mmode)

;; Customize
(defgroup warp nil
  "Warp mode"
  :group 'convenience
  :prefix "warp-")

(defcustom warp-server-port-base 8800
  "Base port number for warp server"
  :type 'integer
  :group 'warp)

(defcustom warp-auto-open-client t
  "Open client in browser when warp-mode is turned on"
  :type 'boolean
  :group 'warp)

(defcustom warp-auto-open-client-delay 3
  "Delay for auto open client"
  :type 'integer
  :group 'warp)

(defcustom warp-auto-close-client t
  "Close client when warp-mode is turned off
Client on Firefox can't support this."
  :type 'boolean
  :group 'warp)

(defcustom warp-html-auto-start-sending nil
  "Start sending html to the server when mode is turned on"
  :type 'boolean
  :group 'warp)

(defcustom warp-idle-time 0.3
  "Time for idle detection on html sending mode"
  :type 'float
  :group 'warp)

(defcustom warp-server-command "warp"
  "Warp server command"
  :type 'string
  :group 'warp)

(defcustom warp-server-command-args nil
  "Arguments for warp server command"
  :type 'list
  :group 'warp)

(defcustom warp-format-converter-alist
  (list
   '("\\.md\\|\\.markdown" (lambda ()
                              '("sundown"))))
  "Alist of converters used for convert specific format to html. The format is:

\(\(\"Filename or Regexp\" \"Function's Symbol which returns convert command\"\)

If warp-mode is enabled on buffer its file name matches \"Filename or Regexp\",
warp-mode convert buffer string to HTML using converter command returned by
associated function before send string to server."
  :type 'list
  :group 'warp)

(defvar warp-mode-hook nil
  "Hook for warp mode")

(define-minor-mode warp-mode
  "Warp minor mode"
  :lighter " Warp"
  :group  'warp
  (if warp-mode
      (progn (warp-start-server)
             (when warp-auto-open-client
                 (progn (sleep-for warp-auto-open-client-delay)
                        (warp-open-client)))
             (when warp-html-auto-start-sending
                 (warp-start-sending-current-buffer))
             (run-hooks 'warp-mode-hook))
    (progn (warp-stop-sending-current-buffer)
           (warp-interrupt-server))))


;; User Command
(defun warp-start-server ()
  "Start warp server for current buffer"
  (interactive)
  (progn (set (make-local-variable 'warp-server-port)
              (warp-get-server-port))
         (set (make-local-variable 'warp-server-process)
              (apply 'warp-start-server-process (current-buffer)
                     "-p" (number-to-string warp-server-port)
                     (append warp-server-command-args
                             (if warp-auto-close-client '("-c") nil))))))

(defun warp-interrupt-server ()
  "Send SIGINT to warp server"
 (interactive)
 (when (warp-process-running-p warp-server-process)
     (interrupt-process warp-server-process)))

(defun warp-send-server-string (string)
  "Send string to warp server's STDIN"
  (interactive "sString send to warp: ")
  (if (warp-process-running-p warp-server-process)
      (process-send-string warp-server-process string)
    (message "Warp: Server not running..")))

(defun warp-send-html (string)
  "Send string as html command data to warp server's STDIN"
  (interactive "sHTML string send to warp: ")
  (unless (string-equal "" string)
          (warp-send-server-string (concat "\n__html__\n" string "\n__endhtml__\n"))))

(defun warp-buffer-string ()
  "Get whole buffer string"
  (save-excursion
    (save-restriction
      (widen) (buffer-string))))

(defun warp-send-current-buffer-as-html ()
  "Send warp server current buffer content as HTML data"
  (interactive)
  (warp-send-html
   (replace-regexp-in-string "[\n]" ""
                             (encode-coding-string (warp-buffer-string) 'utf-8))))

(defun warp-send-current-buffer-converting ()
  "Send warp server current buffer content converting to HTML data."
  (interactive)
  (progn (warp-send-server-string "\n__html__\n")
         (let* ((convert-command
                (funcall (car (assoc-default buffer-file-name
                               warp-format-converter-alist 'string-match))))
               (convert-process
                 (apply 'start-process "warp-convert" (current-buffer) convert-command)))
           (set-process-query-on-exit-flag convert-process nil)
           (set-process-filter convert-process
                               '(lambda (process output)
                                  (warp-send-server-string output)))
           (set-process-sentinel convert-process
                                 '(lambda (process event)
                                    (when (equal (process-status process) 'exit)
                                        (warp-send-server-string "\n__endhtml__\n"))))
           ;; TODO: IF command need stdin
           (process-send-string convert-process (concat (warp-buffer-string) "\n"))
           (process-send-eof convert-process))
         ))

(defun warp-buffer-need-convert ()
  "Determine if conversion is needed for current buffer"
  (not (null (assoc-default buffer-file-name
                         warp-format-converter-alist 'string-match))))

(defun warp-send-current-buffer ()
  "Send warp server current buffer. Convert string if setting for current buffer exist"
  (interactive)
  (if (warp-buffer-need-convert)
      (warp-send-current-buffer-converting)
      (warp-send-current-buffer-as-html)))

(defun warp-start-sending-current-buffer ()
  "Start sending html to the server"
  (interactive)
  (set (make-local-variable 'warp-sending-timer)
       (run-with-idle-timer warp-idle-time t
                       'warp-send-current-buffer)))

(defun warp-stop-sending-current-buffer ()
  "Stop sending html to the server"
  (interactive)
  (when (and (boundp 'warp-sending-timer)
             (timerp warp-sending-timer))
      (cancel-timer warp-sending-timer)))

(defun warp-open-client ()
  "Open warp client within default browser"
  (interactive)
  (if (warp-process-running-p warp-server-process)
      (browse-url (concat "http://localhost:" (number-to-string warp-server-port) "/"))
    (message "Warp: Server not running..")))


;; Fundamental
(defvar warp-server-command-path
  (file-name-directory (or load-file-name "."))
  "Directory of warp server command")

(defvar warp-current-server-port
  warp-server-port-base
  "Current port number for server.
Be sure to get port number by warp-get-server-port.")

(defun warp-get-server-port ()
  "Get next port number for server."
  (setq warp-current-server-port (1+ warp-current-server-port)))

(defun warp-server-process-filter (process output)
  "Receive warp server outputs"
  (message "Warp: %s" (replace-regexp-in-string "\n+$" "" output)))

(defun warp-server-process-sentinel (process event)
  "Sentinel for warp server process.
Now, just for preventing output to be appended to buffer."
  nil)

(defun warp-process-running-p (process)
  "Return if process is running"
  (cond
   ((and (processp process)
        (equal (process-status process) 'run)) t)
   (t nil)))

(defun warp-start-server-process (buffer &rest args)
  "Start warp server and returns server process.
This function takes buffer to which bind server process to.
Pass nil as buffer if you wish no buffer to be bound."
  (let ((process
         (apply 'start-process "warp-server" buffer
                (expand-file-name warp-server-command warp-server-command-path) args)))
    (set-process-query-on-exit-flag process nil)
    (set-process-sentinel process 'warp-server-process-sentinel)
    (set-process-filter process 'warp-server-process-filter) process))

;; Provide
(provide 'warp)