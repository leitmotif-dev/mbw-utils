//
//  CoreDataObject.swift
//
//  Created by John Scalo on 8/6/21.
//

import Foundation
import CoreData

/// An abstract super class for Core Data objects.
open class CoreDataObject: NSManagedObject {
    
    @NSManaged open var id: IDType
        
    open class var entityName: String {
        return "<undefined>"
    }
    
    /// **WARNING**: brings entire object graph into memory. For debugging use only.
    open var coreDataAttrs: String {
        var str = String()
        
        guard let entityName = CoreDataManager.current.entityNameForClass(type(of: self)) else { return "" }
        
        str.append("--\nEntity: \(entityName)\n\n")
        for (key,_) in self.entity.attributesByName {
            let currentValue = self.value(forKey: key)
            str.append("\(key): \(currentValue ?? "nil")\n")
        }
        
        str.append("--\n\n")
        
        return str
    }
    
    open var isPersisted: Bool {
        return !self.objectID.isTemporaryID
    }
    
    
    /// Fetch an object with the given `id` from the store.
    /// - Parameter id: ID of the object to fetch
    /// - Returns: The found object
    open class func fetch(id: IDType) -> Self? {
        guard let entityName = CoreDataManager.current.entityNameForClass(self) else {
            return nil
        }
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "id == %@", id)
        var results: [CoreDataObject]? = nil
        do {
            results = try CoreDataManager.current.mainContext.fetch(fetchRequest) as? [CoreDataObject]
        } catch {
            Logger.fileLog("*** fetch failed: \(error)")
        }
        
        return results?.first as? Self
    }

    convenience public init(id: IDType, entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        self.init(entity: entity, insertInto: context)
        self.id = id
    }
    
    /// Add an object to the store.
    /// If the object already exists (i.e. there's already an object in the store with the same entity type and `id`), the existing object is updated.
    /// - Parameter saveContext: Whether to save the context after inserting. When updating many objects one after the other, set to false and save the context when finished.
    /// - Returns: A tuple containing the inserted object, whether it was newly created or not (vs updated), and an optional error.
    @discardableResult open func insertOrUpdate(saveContext: Bool = true) -> (CoreDataObject?, Bool /* wasCreated */, Error?) {
        assert(Thread.isMainThread)
        let managedObject: CoreDataObject
        var wasCreated = false
        if let existing = Self.fetch(id: self.id) {
            CoreDataManager.current.update(managedObject: existing, with: self)
            managedObject = existing
        } else {
            wasCreated = true
            CoreDataManager.current.mainContext.insert(self)
            managedObject = self
        }
        if saveContext {
            if let error = CoreDataManager.current.save() {
                return (nil, false, error)
            }
        }
        return (managedObject, wasCreated, nil)
    }
    
    /// Delete this object from the store and optionally save the context.
    /// - Parameter saveContext: Whether to save the context after inserting. When updating many objects one after the other, set to false and save the context when finished.
    /// - Returns: An optional error.
    @discardableResult open func delete(saveContext: Bool = true) -> Error? {
        assert(Thread.isMainThread)
        CoreDataManager.current.mainContext.delete(self)
        if saveContext {
            if let error = CoreDataManager.current.save() {
                return error
            }
        }
        return nil
    }
}

