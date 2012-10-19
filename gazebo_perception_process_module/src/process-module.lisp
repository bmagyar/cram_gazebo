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

(in-package :gazebo-perception-process-module)

(defclass perceived-object (object-designator-data) ())
(defclass handle-perceived-object (object-designator-data) ())

(defmethod designator-pose ((designator object-designator))
  (object-pose (reference designator)))

(defmethod designator-distance ((designator-1 object-designator)
                                (designator-2 object-designator))
  (cl-transforms:v-dist (cl-transforms:origin (designator-pose designator-1))
                        (cl-transforms:origin (designator-pose designator-2))))

(defgeneric make-new-desig-description (old-desig perceived-object)
  (:documentation "Merges the description of `old-desig' with the
properties of `perceived-object'")
  (:method ((old-desig object-designator) (po object-designator-data))
    (let ((obj-loc-desig (make-designator 'location
                                          `((pose ,(object-pose po))))))
      (cons `(at ,obj-loc-desig)
            (remove 'at (description old-desig) :key #'car)))))

(defgeneric knowledge-backed-designator (name pose)
  (:documentation "Creates a designator that includes information from
  the knowledge base about an object identified by `name`, which is
  located at pose `pose`.")
  (:method (name (pose tf:pose-stamped))))

(defun make-handled-object-description (&key object-type
                                          object-pose
                                          handles
                                          name
                                          collision-parts)
  "Tailors the description of a handled object into a designator
conforming list."
  (append `((type ,object-type)
            (at ,(make-designator
                  'location
                  `((pose ,object-pose)))))
          `,(make-handle-designator-sequence
             handles)
          `,(make-collision-part-designator-sequence
             collision-parts)
          (when name
            `((name ,name)))))

(defun make-handled-object-designator (&key object-type
                                         object-pose
                                         handles
                                         name)
  "Creates and returns an object designator with object type
`object-type' and object pose `object-pose' and attaches location
designators according to handle information in `handles'."
  (make-designator 'object (make-handled-object-description
                            :object-type object-type
                            :object-pose object-pose
                            :handles handles
                            :name name)))

(defun make-collision-part-designator-sequence (collision-parts)
  (mapcar (lambda (collision-part-desc)
            `(collision-part
              ,(make-designator 'object
                                (append
                                 `((at ,(make-designator
                                         'location
                                         `((pose ,(first collision-part-desc)))))
                                   (type collision-part))
                                 (make-shape-description collision-part-desc)))))
          collision-parts))

(defun make-shape-description (collision-part-desc)
  (let ((shape (second collision-part-desc)))
    (append `((shape ,shape))
            (case shape
              (:cylinder `((radius ,(third collision-part-desc))
                           (length ,(fourth collision-part-desc))))
              (t
               (roslisp:ros-warn
                (gazebo-perception process-module)
                "Unsupported collision description: ~a.~%"
                collision-part-desc))))))

(defun make-handle-designator-sequence (handles)
  "Converts the sequence `handles' (handle-pose handle-radius) into a
sequence of object designators representing handle objects. Each
handle object then consist of a location designator describing its
relative position as well as the handle's radius for grasping
purposes."
  (mapcar (lambda (handle-desc)
            `(handle
              ,(make-designator 'object
                                `((at ,(make-designator
                                        'location
                                        `((pose ,(first handle-desc)))))
                                  (radius ,(second handle-desc))
                                  (type handle)))))
          handles))

(defun find-object (name)
  "Finds the object named `name' in the gazebo world and returns an
instance of PERCEIVED-OBJECT."
  (let ((model-pose (cram-gazebo-utilities::get-model-pose name :test #'object-names-equal)))
    (when model-pose
      (make-instance 'perceived-object
                     :pose model-pose
                     :object-identifier name))))

(defmethod make-new-desig-description ((old-desig object-designator)
                                       (perceived-object perceived-object))
  (let ((description (call-next-method)))
    (if (member 'name description :key #'car)
        description
        (cons `(name ,(object-identifier perceived-object)) description))))

(defmethod knowledge-backed-designator (name (pose tf:pose-stamped))
  (force-ll (lazy-mapcar
             (lambda (bindings)
               (with-vars-bound (?object ?handles ?type ?collision-parts) bindings
                 (declare (ignore ?object))
                 (with-designators ((kb-desig (object (make-handled-object-description
                                                       :object-type ?type
                                                       :object-pose pose
                                                       :handles ?handles
                                                       :name name
                                                       :collision-parts ?collision-parts
                                                       ))))
                   kb-desig)))
             (prolog `(and (simple-knowledge::gazebo-object ?object ?name ?type)
                           (simple-knowledge::object-handles ?name ?handles)
                           (simple-knowledge::object-collision-parts ?name ?collision-parts))
                     `(,@(when name `((?name . ,name))))))))

(defun perceived-object->designator (designator perceived-object)
  (make-effective-designator
   designator
   :new-properties (make-new-desig-description designator perceived-object)
   :data-object perceived-object))

(defun find-with-designator (designator)
  ;; Since gazebo does not provide object types and we do not have a
  ;; knowledge base for that yet.
  ;;
  ;; TODO(moesenle): add verification of location using the AT
  ;; property.
  (with-desig-props (name) designator
    (let* ((perceived-object (find-object name))
           (detailed-designators (knowledge-backed-designator
                                  name
                                  (object-pose perceived-object))))
      (if perceived-object
          (mapcar (lambda (details)
                    (perceived-object->designator details perceived-object))
                  detailed-designators)
          (fail 'object-not-found :object-desig designator)))))

(defun emit-perception-event (designator)
  (cram-plan-knowledge:on-event (make-instance
                                 'cram-plan-knowledge:object-perceived-event
                                 :perception-source :gazebo-perception-process-module
                                 :object-designator designator))
  designator)

(def-process-module gazebo-perception-process-module (input)
  (assert (typep input 'action-designator))
  (let ((object-designator (reference input)))
    (ros-info (gazebo-perception-process-module process-module)
              "Searching for object ~a" object-designator)
    (let ((result (find-with-designator object-designator)))
      (ros-info (gazebo-perception-process-module process-module)
                "Found objects: ~a" result)
      (emit-perception-event result)
      result)))
