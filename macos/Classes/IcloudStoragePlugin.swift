import Flutter
import UIKit

public class IcloudStoragePlugin: NSObject, FlutterPlugin {
  var containerId = ""
  var listStreamHandler: StreamHandler?
  var messenger: FlutterBinaryMessenger?
  var streamHandlers: [String: StreamHandler] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let channel = FlutterMethodChannel(name: "icloud_storage", binaryMessenger: messenger)
    let instance = SwiftIcloudStoragePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.messenger = messenger
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      initialize(call, result)
    case "gatherFiles":
      gatherFiles(call, result)
    case "listFiles":
      listFiles(call, result)
    case "upload":
      upload(call, result)
    case "download":
      download(call, result)
    case "delete":
      delete(call, result)
    case "move":
      move(call, result)
    case "createEventChannel":
      createEventChannel(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
  
  private func initialize(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let containerId = args["containerId"] as? String
    else {
      result(argumentError)
      return
    }
    self.containerId = containerId
    result(nil)
  }
  
  private func gatherFiles(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    addGatherFilesObservers(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
    
    if !eventChannelName.isEmpty {
      let streamHandler = self.streamHandlers[eventChannelName]!
      streamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
    }
    query.start()
  }
  
  private func addGatherFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) {
      [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        removeObservers(query, watchUpdate: false)
        if eventChannelName.isEmpty { query.stop() }
        result(files)
    }
    
    if !eventChannelName.isEmpty {
      NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) {
        [self] (notification) in
        let files = mapFileAttributesFromQuery(query: query, containerURL: containerURL)
        let streamHandler = self.streamHandlers[eventChannelName]!
        streamHandler.setEvent(files)
      }
    }
  }
  
  private func mapFileAttributesFromQuery(query: NSMetadataQuery, containerURL: URL) -> [[String: Any?]] {
    var fileMaps: [[String: Any?]] = []
    for item in query.results {
      guard let fileItem = item as? NSMetadataItem else { continue }
      guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
      if fileURL.absoluteString.last == "/" { continue }

      let map: [String: Any?] = [
        "relativePath": String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count)),
        "sizeInBytes": fileItem.value(forAttribute: NSMetadataItemFSSizeKey),
        "creationDate": (fileItem.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date)?.timeIntervalSince1970,
        "contentChangeDate": (fileItem.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date)?.timeIntervalSince1970,
        "hasUnresolvedConflicts": fileItem.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey),
        "downloadStatus": fileItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey),
        "isDownloading": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey),
        "isUploaded": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey),
        "isUploading": fileItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey),
      ]
      fileMaps.append(map)
    }
    return fileMaps
  }

  @available(*, deprecated)
  private func listFiles(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(format: "%K beginswith %@", NSMetadataItemPathKey, containerURL.path)
    addListFilesObservers(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
    
    if !eventChannelName.isEmpty {
      let streamHandler = self.streamHandlers[eventChannelName]!
      streamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
      result(nil)
    }
    query.start()
  }
  
  @available(*, deprecated)
  private func addListFilesObservers(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) {
      [self] (notification) in
      onListQueryNotification(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
    }
    
    if !eventChannelName.isEmpty {
      NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) {
        [self] (notification) in
        onListQueryNotification(query: query, containerURL: containerURL, eventChannelName: eventChannelName, result: result)
      }
    }
  }

  @available(*, deprecated)
  private func onListQueryNotification(query: NSMetadataQuery, containerURL: URL, eventChannelName: String, result: @escaping FlutterResult) {
    var filePaths: [String] = []
    for item in query.results {
      guard let fileItem = item as? NSMetadataItem else { continue }
      guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
      if fileURL.absoluteString.last == "/" { continue }
      let relativePath = String(fileURL.absoluteString.dropFirst(containerURL.absoluteString.count))
      filePaths.append(relativePath)
    }
    if !eventChannelName.isEmpty {
      let streamHandler = self.streamHandlers[eventChannelName]!
      streamHandler.setEvent(filePaths)
    } else {
      removeObservers(query, watchUpdate: false)
      query.stop()
      result(filePaths)
    }
  }
  
  private func upload(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let localFilePath = args["localFilePath"] as? String,
          let cloudFileName = args["cloudFileName"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    let localFileURL = URL(fileURLWithPath: localFilePath)
    
    do {
      if FileManager.default.fileExists(atPath: cloudFileURL.path) {
        try FileManager.default.removeItem(at: cloudFileURL)
      } else {
        let cloudFileDirURL = cloudFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: cloudFileDirURL.path) {
          try FileManager.default.createDirectory(at: cloudFileDirURL, withIntermediateDirectories: true, attributes: nil)
        }
      }
      try FileManager.default.copyItem(at: localFileURL, to: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
    }
    
    if !eventChannelName.isEmpty {
      let query = NSMetadataQuery.init()
      query.operationQueue = .main
      query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
      query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
      
      let uploadStreamHandler = self.streamHandlers[eventChannelName]!
      uploadStreamHandler.onCancelHandler = { [self] in
        removeObservers(query)
        query.stop()
        removeStreamHandler(eventChannelName)
      }
      addUploadObservers(query: query, eventChannelName: eventChannelName)
      
      query.start()
    }
    
    result(nil)
  }
  
  private func addUploadObservers(query: NSMetadataQuery, eventChannelName: String) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
      onUploadQueryNotification(query: query, eventChannelName: eventChannelName)
    }
  }
  
  private func onUploadQueryNotification(query: NSMetadataQuery, eventChannelName: String) {
    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemIsUploadingKey]) else { return}
    guard let streamHandler = self.streamHandlers[eventChannelName] else { return }
    
    if let error = fileURLValues.ubiquitousItemUploadingError {
      streamHandler.setEvent(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double {
      streamHandler.setEvent(progress)
      if (progress >= 100) {
        streamHandler.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
      }
    }
  }
  
  private func download(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let cloudFileName = args["cloudFileName"] as? String,
          let localFilePath = args["localFilePath"] as? String,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let cloudFileURL = containerURL.appendingPathComponent(cloudFileName)
    do {
      try FileManager.default.startDownloadingUbiquitousItem(at: cloudFileURL)
    } catch {
      result(nativeCodeError(error))
    }
    
    let query = NSMetadataQuery.init()
    query.operationQueue = .main
    query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
    query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemPathKey, cloudFileURL.path)
    
    let downloadStreamHandler = self.streamHandlers[eventChannelName]
    downloadStreamHandler?.onCancelHandler = { [self] in
      removeObservers(query)
      query.stop()
      removeStreamHandler(eventChannelName)
    }

    let localFileURL = URL(fileURLWithPath: localFilePath)
    addDownloadObservers(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
    
    query.start()
    result(nil)
  }
  
  private func addDownloadObservers(query: NSMetadataQuery, cloudFileURL: URL, localFileURL: URL, eventChannelName: String) {
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query, queue: query.operationQueue) { [self] (notification) in
      onDownloadQueryNotification(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
    }
    
    NotificationCenter.default.addObserver(forName: NSNotification.Name.NSMetadataQueryDidUpdate, object: query, queue: query.operationQueue) { [self] (notification) in
      onDownloadQueryNotification(query: query, cloudFileURL: cloudFileURL, localFileURL: localFileURL, eventChannelName: eventChannelName)
    }
  }
  
  private func onDownloadQueryNotification(query: NSMetadataQuery, cloudFileURL: URL, localFileURL: URL, eventChannelName: String) {
    if query.results.count == 0 {
      return
    }
    
    guard let fileItem = query.results.first as? NSMetadataItem else { return }
    guard let fileURL = fileItem.value(forAttribute: NSMetadataItemURLKey) as? URL else { return }
    guard let fileURLValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingStatusKey]) else { return }
    let streamHandler = self.streamHandlers[eventChannelName]
    
    if let error = fileURLValues.ubiquitousItemDownloadingError {
      streamHandler?.setEvent(nativeCodeError(error))
      return
    }
    
    if let progress = fileItem.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double {
      streamHandler?.setEvent(progress)
    }
    
    if fileURLValues.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
      do {
        try moveCloudFile(at: cloudFileURL, to: localFileURL)
        streamHandler?.setEvent(FlutterEndOfEventStream)
        removeStreamHandler(eventChannelName)
      } catch {
        streamHandler?.setEvent(nativeCodeError(error))
      }
    }
  }
  
  private func moveCloudFile(at: URL, to: URL) throws {
    do {
      if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
      }
      try FileManager.default.copyItem(at: at, to: to)
    } catch {
      throw error
    }
  }
  
  private func delete(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let cloudFileName = args["cloudFileName"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let fileURL = containerURL.appendingPathComponent(cloudFileName)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: fileURL, options: NSFileCoordinator.WritingOptions.forDeleting, error: nil) {
      writingURL in
      do {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: writingURL.path, isDirectory: &isDir) {
          result(fileNotFoundError)
          return
        }
        try FileManager.default.removeItem(at: writingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func move(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let atRelativePath = args["atRelativePath"] as? String,
          let toRelativePath = args["toRelativePath"] as? String
    else {
      result(argumentError)
      return
    }
    
    guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
    else {
      result(containerError)
      return
    }
    DebugHelper.log("containerURL: \(containerURL.path)")
    
    let atURL = containerURL.appendingPathComponent(atRelativePath)
    let toURL = containerURL.appendingPathComponent(toRelativePath)
    let fileCoordinator = NSFileCoordinator(filePresenter: nil)
    fileCoordinator.coordinate(writingItemAt: atURL, options: NSFileCoordinator.WritingOptions.forMoving, writingItemAt: toURL, options: NSFileCoordinator.WritingOptions.forReplacing, error: nil) {
      atWritingURL, toWritingURL in
      do {
        let toDirURL = toWritingURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: toDirURL.path) {
          try FileManager.default.createDirectory(at: toDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        try FileManager.default.moveItem(at: atWritingURL, to: toWritingURL)
        result(nil)
      } catch {
        DebugHelper.log("error: \(error.localizedDescription)")
        result(nativeCodeError(error))
      }
    }
  }
  
  private func removeObservers(_ query: NSMetadataQuery, watchUpdate: Bool = true){
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidFinishGathering, object: query)
    if watchUpdate {
      NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSMetadataQueryDidUpdate, object: query)
    }
  }
  
  private func createEventChannel(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? Dictionary<String, Any>,
          let eventChannelName = args["eventChannelName"] as? String
    else {
      result(argumentError)
      return
    }
    
    let streamHandler = StreamHandler()
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: self.messenger!)
    eventChannel.setStreamHandler(streamHandler)
    self.streamHandlers[eventChannelName] = streamHandler
    
    result(nil)
  }
  
  private func removeStreamHandler(_ eventChannelName: String) {
    self.streamHandlers[eventChannelName] = nil
  }
  
  let argumentError = FlutterError(code: "E_ARG", message: "Invalid Arguments", details: nil)
  let containerError = FlutterError(code: "E_CTR", message: "Invalid containerId, or user is not signed in, or user disabled iCould permission", details: nil)
  let fileNotFoundError = FlutterError(code: "E_FNF", message: "The file does not exist", details: nil)
  
  private func nativeCodeError(_ error: Error) -> FlutterError {
    return FlutterError(code: "E_NAT", message: "Native Code Error", details: "\(error)")
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  private var _eventSink: FlutterEventSink?
  var onCancelHandler: (() -> Void)?
  
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    _eventSink = events
    DebugHelper.log("on listen")
    return nil
  }
  
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    onCancelHandler?()
    _eventSink = nil
    DebugHelper.log("on cancel")
    return nil
  }
  
  func setEvent(_ data: Any) {
    _eventSink?(data)
  }
}

class DebugHelper {
  public static func log(_ message: String) {
    #if DEBUG
    print(message)
    #endif
  }
}

