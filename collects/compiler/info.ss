
(lambda (request)
  (case request
    [(name) "mzc"]
    [(compile-prefix) '(begin
			 (require-library "match.ss")
			 (require-library "zsigs.ss" "zodiac")
			 (require-library "sigs.ss" "zodiac"))]
    [(compile-omit-files) 
     null]
    [else (error 'mzc-info "Unknown request: ~s" request)]))
