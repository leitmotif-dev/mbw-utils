//
//  CoreDataManager.swift
//
//  Created by John Scalo on 8/6/21.
//

import CoreData

public typealias IDType = String

/** A convenience class that manages Core Data stores.
 
 `CoreDataManager` makes some assumptions about how the CD store is managed:
 
 * The MOC is concurrent with the main thread
 * It uses an overwrite merge policy
 * It uses sqlite as the backing store
 
 `CoreDataManager` and `CoreDataObject` work together so all entities managed through `CoreDataManager` should be subclasses of  `CoreDataObject`.
*/
public class CoreDataManager {
    
    // For convenience, assuming there's only ever one in the app
    public static var current: CoreDataManager!
    
    public var mainContext: NSManagedObjectContext!
        
    /// Instantiate a CoreDataManager.
    /// - Parameter modelName: the name of the CoreData model resource file
    /// - Parameter dbName: the name to use for the sqlite database stored on disk
    public init(modelName: String, dbName: String) {
        guard let modelURL = Bundle.main.url(forResource: modelName,
                                             withExtension: "momd") else {
            fatalError("Failed to locate DataModel in app bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to initialize MOM")
        }
        let psc = NSPersistentStoreCoordinator(managedObjectModel: mom)
        
        mainContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        mainContext?.persistentStoreCoordinator = psc
        mainContext?.mergePolicy = NSOverwriteMergePolicy // prevents merge errors
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to resolve documents directory")
        }
        let storeURL = documentsURL.appendingPathComponent(dbName)
        Logger.shortLog("Core Data db path: \(storeURL.path)")
        
        do {
            let options = [NSMigratePersistentStoresAutomaticallyOption: true,
                           NSInferMappingModelAutomaticallyOption: true]
            try psc.addPersistentStore(ofType: NSSQLiteStoreType,
                                       configurationName: nil, at: storeURL, options: options)
        } catch let error as NSError {
            fatalError("Failed to add persistent store: \(error)")
        }
        
        CoreDataManager.current = self
    }
    
    /// Update an object in the store
    /// - Parameters:
    ///   - managedObject: The object currently in the store to be updated
    ///   - newObject: The object to update to
    public func update(managedObject: NSManagedObject, with newObject: NSManagedObject) {
        let entity = managedObject.entity
        for (key,_) in entity.attributesByName {
            let newValue = newObject.value(forKey: key)
            managedObject.setValue(newValue, forKey: key)
        }
    }
    
    /// Replace an object in the store
    /// - Parameters:
    ///   - managedObject: The object currently in the store to be replaced
    ///   - newObject: The object to replace it with
    public func replace(managedObject: NSManagedObject, with newObject: NSManagedObject) {
        mainContext.delete(managedObject)
        do { try mainContext.save() } catch {
            Logger.fileLog("*** Caught: \(error)")
        }
    }
    
    /// Persist objects in the context
    /// - Returns: An optional error
    @discardableResult public func save() -> Error? {
        assert(Thread.isMainThread)
        do {
            try mainContext.save()
        } catch {
            Logger.fileLog("*** failure to save context: \(error)")
            return error
        }
        return nil
    }
    
    /// Print all objects in the store to console. **WARNING**: brings entire object graph into memory. For debugging use only.
    public func printAllObjects() {
        guard let model = mainContext.persistentStoreCoordinator?.managedObjectModel else {
            Logger.fileLog("*** persistentStoreCoordinator was nil")
            return
        }
        for nextEntityName in model.entities.compactMap({ $0.name }) {
            if nextEntityName == "CoreDataObject" {
                // Skip the abstract superclass since it's redundant
                continue
            }
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: nextEntityName)
            if let results = try? mainContext.fetch(fetchRequest) {
                for next in results {
                    if let o = next as? CoreDataObject {
                        print(o.coreDataAttrs)
                    } else {
                        print("*** warning, not a Core Data object: \(next)")
                    }
                }
            }
        }
    }

    /// Use with extreme care. Deleting objects with remaining references from other objects will result in an exception. Further, all relationship entities that these objects reference will also be deleted.
    /// - Parameter entityName: The name of the entity for which all objects are to be deleted
    public func deleteAllObjects(entityName: String) {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        do {
            try mainContext.execute(request)
            if let error = save() {
                throw(error)
            }
        } catch {
            Logger.fileLog("*** deleteAll() failed with \(error)")
        }
    }
    
    /// Use with extreme care. For debugging/tests purposes only.
    public func deleteAll() {
        deleteAllObjects(entityName: "CoreDataObject")
        mainContext.reset()
    }
}
