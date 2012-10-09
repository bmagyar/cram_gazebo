;;; Copyright (c) 2012, Jan Winkler <winkler@cs.uni-bremen.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of Willow Garage, Inc. nor the names of its
;;;       contributors may be used to endorse or promote products derived from
;;;       this software without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :simple-knowledge)

(defvar *object-list* () "List of objects in the knowledge backend database")

(defclass gazebo-object-information ()
  ((object-name :reader object-name :initarg :object-name)
   (object-type :reader object-type :initarg :object-type)
   (handles :reader handles :initarg :handles)
   (object-pose :reader object-pose :initarg :object-pose)
   (filename :reader filename :initarg :filename)))

(defun clear-object-list ()
  (setf *object-list* ()))

(defun add-object-to-spawn (&key name handles type pose file)
  (setf *object-list*
        (append *object-list*
		(list (make-instance 'gazebo-object-information
				     :object-name name
				     :object-type type
				     :handles handles
				     :object-pose pose
				     :filename file)))))

(defun objects-with-type (type)
  (force-ll (crs:prolog `(object-type ?name ,type))))

(defun object-type-for-name (name)
  (force-ll (crs:prolog `(object-type ,name ?type))))

(defun spawn-objects ()
  (loop for object-data in *object-list*
        do (spawn-object object-data)))

(defun spawn-object (object-data)
  ;; NOTE(winkler): First check to see whether the object to be
  ;; spawned is already present in the gazebo world (i.e. if there is
  ;; an object of the same name, as this is the only differentiation
  ;; gazebo does for objects).
  (let ((object-spawned
          (eq (crs:prolog
               `(gazebo-perception-process-module::object-in-world?
                 ,(object-name object-data))) nil)))
    (when object-spawned
      (cram-gazebo-utilities::spawn-gazebo-model
       (object-name object-data)
       (object-pose object-data)
       (filename object-data)))))

(defun reposition-objects ()
  (loop for object-data in *object-list*
        do (cram-gazebo-utilities::set-model-state
            (object-name object-data)
            (object-pose object-data))))
