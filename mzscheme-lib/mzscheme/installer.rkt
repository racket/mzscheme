#lang racket/base
(require launcher
         compiler/embed
         racket/file
         racket/path)

(provide post-installer)

(define (post-installer path coll user?)
  (define variants (available-mzscheme-variants))
  (for ([v (in-list variants)])
    (parameterize ([current-launcher-variant v])
      (create-embedding-executable
       (prep-dir (mzscheme-program-launcher-path "MzScheme" #:user? user?))
       #:variant v
       #:cmdline '("-I" "scheme/init")
       #:launcher? #t
       #:aux '((framework-root . #f)
               (dll-dir . #f)
               (relative? . #t))))))

(define (prep-dir p)
  (define dir (path-only p))
  (make-directory* dir)
  p)
