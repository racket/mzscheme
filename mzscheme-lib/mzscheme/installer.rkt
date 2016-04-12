#lang racket/base
(require launcher
         compiler/embed
         racket/file
         racket/path
         setup/dirs)

(provide installer)

(define (installer path coll user? no-main?)
  (unless no-main?
    (do-installer path coll user? #f)
    (when (and (not user?)
               (find-config-tethered-console-bin-dir))
      (do-installer path coll #f #t)))
  (when (find-addon-tethered-console-bin-dir)
    (do-installer path coll #t #t)))

(define (do-installer path coll user? tethered?)
  (define variants (available-mzscheme-variants))
  (for ([v (in-list variants)])
    (parameterize ([current-launcher-variant v])
      (create-embedding-executable
       (prep-dir (mzscheme-program-launcher-path "MzScheme" #:user? user? #:tethered? tethered?))
       #:variant v
       #:cmdline (append
                  (if (or user? tethered?)
                      (list "-X" (path->string (find-collects-dir))
                            "-G" (path->string (find-config-dir)))
                      null)
                  (if (and tethered? user?)
                      (list "-A" (path->string (find-system-path 'addon-dir)))
                      null)
                  '("-I" "scheme/init"))
       #:launcher? #t
       #:aux (append
              (if (or user? tethered?)
                  null
                  `((framework-root . #f)
                    (dll-dir . #f)))
              `((relative? . ,(not (or user? tethered?)))))))))

(define (prep-dir p)
  (define dir (path-only p))
  (make-directory* dir)
  p)
