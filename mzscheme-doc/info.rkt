#lang info

(define collection 'multi)

(define deps '("base"))

(define pkg-desc "documentation part of \"mzscheme\"")

(define pkg-authors '(mflatt))
(define build-deps '("compatibility-lib"
                     "r5rs-doc"
                     "r5rs-lib"
                     "racket-doc"
                     "scheme-lib"
                     "scheme-doc"
                     "scribble-lib"))

(define license
  '(Apache-2.0 OR MIT))
