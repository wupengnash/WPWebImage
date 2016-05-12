//
//  WPWebImage.swift
//  ArtCircle
//
//  Created by wupeng on 16/1/29.
//
//

import UIKit
import ImageIO
import MobileCoreServices
import AssetsLibrary

public enum CacheType {
    case None, Memory, Disk
}

public typealias DownloadProgressBlock = ((receivedSize: Int64, totalSize: Int64) -> ())
public typealias CompletionHandler = ((image: UIImage?, error: NSError?, cacheType: CacheType, imageURL: NSURL?) -> ())

extension String {
    func length() -> Int  {
        return self.characters.count
    }
}
extension UIButton {
    /**
     渐变设置图片第二种方法
     
     - parameter duration:
     */
    func addTransition(duration:NSTimeInterval,transionStyle:WPCATransionStyle = .Fade) {
        if self.layer.animationForKey(transionStyle.rawValue) == nil && transionStyle != .None {
            let transition = CATransition()
            transition.type = transionStyle.rawValue
            transition.duration = duration
            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            self.layer.addAnimation(transition, forKey: transionStyle.rawValue)
        }
    }
    func removeTransition(transionStyle:WPCATransionStyle = .Fade) {
        if self.layer.animationForKey(transionStyle.rawValue) != nil {
            self.layer.removeAnimationForKey(transionStyle.rawValue)
        }
    }
    /**
     自定义的异步加载图片
     
     - parameter urlString:        url
     - parameter placeholderImage: 默认图
     */
    func wp_setBackgroundImageWithURL(urlString: String,
        forState state:UIControlState,
        autoSetImage:Bool = true,
        withTransformStyle transformStyle:WPCATransionStyle = .Fade,
        duration:NSTimeInterval = 1.0,
        placeholderImage: UIImage? = UIColor.imageWithColor(UIColor.randomColor()),
        completionHandler:((image:UIImage) ->Void)? = nil) {
            guard urlString != "" else {
                self.setBackgroundImage(placeholderImage, forState: state)
                return
            }
            if self.tag != urlString.hash {
                //解决reloaddata的时候imageview 闪烁问题
                self.tag = urlString.hash
                self.setBackgroundImage(placeholderImage, forState: state)
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                if WPCache.imageExistWithKey(urlString) {
                    WPCache.getDiskCacheObjectForKey(urlString, withSuccessHandler: { (image, key, filePath) -> Void in
                        if self.tag == urlString.hash {
                            if autoSetImage {
                                if filePath == "" {
                                    //内存中取出
                                    self.removeTransition()
                                    self.setBackgroundImage(image, forState: state)
                                } else {
                                    //硬盘中取出
                                    switch transformStyle {
                                    case .None:
                                        self.removeTransition()
                                    case .Fade:
                                        self.addTransition(duration)
                                    default:
                                        self.removeTransition()
                                    }
                                    self.setBackgroundImage(image, forState: state)
                                }
                                if completionHandler != nil {
                                    completionHandler!(image: image)
                                }
                            } else {
                                if completionHandler != nil {
                                    completionHandler!(image: image)
                                }
                            }
                        }
                    })
                } else {
                    if urlString.length() <= 0 {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.setBackgroundImage(placeholderImage, forState: state)
                        })
                    } else {
                        WPWebImage.downloadImage(urlString, withSuccessColsure: { (image, imageData,saveUrl) -> Void in
                            dispatch_async(dispatch_get_global_queue(0, 0), { () -> Void in
                                let newImage = WPWebImage.wp_animatedImageWithGIFData(gifData: imageData)
                                if self.tag == urlString.hash {
                                    if autoSetImage {
                                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                            switch transformStyle {
                                            case .Fade:
                                                self.addTransition(duration)
                                                self.setBackgroundImage(newImage, forState: state)
                                            default:
                                                self.removeTransition()
                                                self.setBackgroundImage(newImage, forState: state)
                                            }
                                        })
                                    }
                                    WPCache.setDiskCacheObject(imageData, ForKey: urlString, withSuccessHandler: { (image, key, filePath) -> Void in
                                        if completionHandler != nil {
                                            completionHandler!(image: image)
                                        }
                                    })
                                }
                            })
                        })
                    }
                }
            }
    }
}
extension UIColor {
    static func randomColor() -> UIColor {
        return UIColor(red: (CGFloat)(arc4random() % 254 + 1)/255.0, green: (CGFloat)(arc4random() % 254 + 1)/255.0, blue: (CGFloat)(arc4random() % 254 + 1)/255.0, alpha: CGFloat.max)
    }
    static func imageWithColor(imageColor:UIColor) -> UIImage {
        let rect = CGRect(x: CGFloat.min, y: CGFloat.min, width: 1.0, height: 1.0)
        UIGraphicsBeginImageContext(rect.size)
        let context:CGContextRef = UIGraphicsGetCurrentContext()!
        CGContextSetFillColorWithColor(context, imageColor.CGColor)
        CGContextFillRect(context, rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
}

class WPCache: NSObject {
    let userDefault = NSUserDefaults.standardUserDefaults()
    class func setStickConversation(conversationID:String) {
        WPCache.sharedInstance.userDefault.setObject(NSNumber(bool: true), forKey: "STICKY\(conversationID)")
    }
    class func getStickConversation(conversationID:String) -> Bool {
        if let stick = WPCache.sharedInstance.userDefault.objectForKey("STICKY\(conversationID)") as? NSNumber {
            return stick.boolValue
        } else {
            return false
        }
    }
    class func desetStickConversation(conversationID:String) {
        WPCache.sharedInstance.userDefault.setObject(NSNumber(bool: false), forKey: "STICKY\(conversationID)")
    }
    let defaultCache = NSCache()
    static let sharedInstance = {
        return WPCache()
    }()
    override init() {
        super.init()
        self.defaultMemoryCache.countLimit = 100
        self.defaultMemoryCache.totalCostLimit = 80
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("terminateCleanDisk"), name: UIApplicationWillTerminateNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("cleanDisk"), name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("clearMemory"), name: UIApplicationDidReceiveMemoryWarningNotification, object: nil)
    }
    func clearMemory() {
        self.defaultMemoryCache.removeAllObjects()
    }
    /**
     清理磁盘缓存方法
     
     - parameter expirCacheAge:
     - parameter completionColsure:
     */
    static func cleanDiskWithCompeletionColsure(expirCacheAge:NSInteger = WPCache.sharedInstance.maxCacheAge,completionColsure:(()->Void)? = nil) {
        dispatch_async(dispatch_get_global_queue(0, 0)) { () -> Void in
            let diskCacheurl = NSURL(fileURLWithPath: WPCache.sharedInstance.cacheDir, isDirectory: true)
            let resourceKeys = [NSURLIsDirectoryKey,NSURLContentModificationDateKey,NSURLTotalFileAllocatedSizeKey]
            let fileManager = NSFileManager.defaultManager()
            let fileEnumerator = fileManager.enumeratorAtURL(diskCacheurl, includingPropertiesForKeys: resourceKeys, options: NSDirectoryEnumerationOptions.SkipsHiddenFiles, errorHandler: nil)
            var fileUrls = [NSURL]()
            while let fileUrl = fileEnumerator?.nextObject() as? NSURL {
                fileUrls.append(fileUrl)
            }
            let expirationDate = NSDate(timeIntervalSinceNow: -NSTimeInterval(expirCacheAge))
            var urlsToDelegate = [NSURL]()
            for (_,url) in fileUrls.enumerate() {
                do {
                    let resourceValues = try url.resourceValuesForKeys(resourceKeys)
                    let moditfyDate = resourceValues[NSURLContentModificationDateKey] as! NSDate
                    if moditfyDate.laterDate(expirationDate) .isEqualToDate(expirationDate) {
                        urlsToDelegate.append(url)
                    }
                } catch _ {}
            }
            for (_,deleteUrl) in urlsToDelegate.enumerate() {
                do {
                    try fileManager.removeItemAtURL(deleteUrl)
                    print("删除照片：\(deleteUrl.absoluteString)")
                } catch _ {}
            }
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                if completionColsure != nil {
                    completionColsure!()
                }
            })
        }
    }
    func terminateCleanDisk() {
        WPCache.cleanDiskWithCompeletionColsure(0, completionColsure: nil)
    }
    func cleanDisk() {
        WPCache.cleanDiskWithCompeletionColsure()
    }
    /// 最大保留秒数7天
    let maxCacheAge : NSInteger = 3600 * 7
    let defaultMemoryCache = NSCache()
    let defaultDiskCache = NSFileManager()
    var diskCacheDirName = "" {
        didSet {
            self.cacheDir = NSTemporaryDirectory().stringByAppendingString("\(self.diskCacheDirName)/")
            if !self.defaultDiskCache.fileExistsAtPath(self.diskCacheDirName) {
                do {
                    try self.defaultDiskCache.createDirectoryAtPath(self.cacheDir, withIntermediateDirectories: true, attributes: nil)
                } catch _ {}
            }
        }
    }
    var cacheDir = "" {
        didSet {
            
        }
    }
    static func imageExistWithKey(key:String) -> Bool {
        if WPCache.sharedInstance.diskCacheDirName == "" {
            WPCache.sharedInstance.diskCacheDirName = "defaultCache"
        }
        let filePath = WPCache.sharedInstance.cacheDir.stringByAppendingString("\(key.hashValue)")
        return  WPCache.sharedInstance.defaultDiskCache.fileExistsAtPath(filePath)
    }
    static func setDiskCacheObject(imageData:NSData , ForKey key:String ,withSuccessHandler successColsure:((image:UIImage,key:String,filePath:String) -> Void)) {
        dispatch_async(dispatch_get_global_queue(0, 0)) { () -> Void in
            if WPCache.sharedInstance.diskCacheDirName == "" {
                WPCache.sharedInstance.diskCacheDirName = "defaultCache"
            }
            let filePath = WPCache.sharedInstance.cacheDir.stringByAppendingString("\(key.hashValue)")
            let result = WPCache.sharedInstance.defaultDiskCache.createFileAtPath(filePath, contents: imageData, attributes: nil)
            //        let result = imageData.writeToFile(filePath, atomically: true)
            if result {
                print("写入成功，\(key),\(filePath)")
                let image = WPWebImage.wp_animatedImageWithGIFData(gifData: imageData)
                WPCache.sharedInstance.defaultMemoryCache.setObject(image!, forKey: key)
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    successColsure(image: UIImage(data: imageData)!,key: key,filePath: filePath)
                })
            } else {
                print("写入失败，\(key),\(filePath)")
            }
        }
    }
    static func getDiskCacheObjectForKey(key:String,withSuccessHandler successColsure:((image:UIImage,key:String,filePath:String) -> Void)) {
        dispatch_async(dispatch_get_global_queue(0, 0)) { () -> Void in
            if WPCache.sharedInstance.diskCacheDirName == "" {
                WPCache.sharedInstance.diskCacheDirName = "defaultCache"
            }
            if WPCache.sharedInstance.defaultMemoryCache.objectForKey(key) != nil {
                let image = WPCache.sharedInstance.defaultMemoryCache.objectForKey(key) as! UIImage
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    successColsure(image: image,key: key,filePath: "")
                })
            } else {
                let filePath = WPCache.sharedInstance.cacheDir.stringByAppendingString("\(key.hashValue)")
                let imageData = WPCache.sharedInstance.defaultDiskCache.contentsAtPath(filePath)
                let image = WPWebImage.wp_animatedImageWithGIFData(gifData: imageData!)
                WPCache.sharedInstance.defaultMemoryCache.setObject(image!, forKey: key)
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    successColsure(image: image!,key: key,filePath: filePath)
                })
            }
        }
    }
}

class WPWebImage: NSObject {
    /**
     下载图片
     
     - parameter urlString: 图片url
     - parameter colsure:   回调
     */
    class func downloadImage(urlString:String,withSuccessColsure colsure:(image:UIImage,imageData:NSData,url:String) -> Void) {
        let url = NSURL(string: urlString)
        let request = NSURLRequest(URL: url!)
        let queue = NSOperationQueue()
        NSURLConnection.sendAsynchronousRequest(request, queue: queue) { (response, data, error ) -> Void in
            if data != nil {
                let image = WPWebImage.wp_animatedImageWithGIFData(gifData: data!)
                if image != nil {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        colsure(image: image!, imageData: data!,url: urlString)
                    })
                }
            }
        }
    }
    /**
     GIF适配
     CG 框架是不会在ARC下被管理，因此此处GIF时会导致内存泄漏  20160401
     证明在OC下确实如此   http://stackoverflow.com/questions/1263642/releasing-cgimage-cgimageref
     Swift 下面被ARC自动管理释放  http://stackoverflow.com/questions/24900595/swift-cgpathrelease-and-arc
     但是在GIF下面内存暴涨很厉害 ，GifU的解决方案：https://github.com/kaishin/Gifu/pull/55
     
     解决方案描述：
     Although the deinit block called displayLink.invalidate(), because the CADisplayLink was retaining the AnimatableImageView instance the view was never deallocated, its deinit block never executed, and .invalidate() was never called.
     
     
     
     We can fix the retention cycle between AnimatableImageView and CADisplayLink by using another object as the target for the CADisplayLink instance, as described here.
     自定义一个CADispaylink 手动管理
     它自定义一个类继承自UIImageView，目前方法考虑UIImageView扩展模仿其实现方法重写
     - parameter data:
     
     - returns:
     */
    class func wp_animatedImageWithGIFData(gifData data: NSData) -> UIImage! {
        let options: NSDictionary = [kCGImageSourceShouldCache as String: NSNumber(bool: true), kCGImageSourceTypeIdentifierHint as String: kUTTypeGIF]
        guard let imageSource = CGImageSourceCreateWithData(data as CFDataRef, options) else {
            return nil
        }
        let frameCount = CGImageSourceGetCount(imageSource)
        var images = [UIImage]()
        let duration = 0.1 * Double(frameCount)
        
        for i in 0 ..< frameCount {
            guard let imageRef  = CGImageSourceCreateImageAtIndex(imageSource, i, options) else {
                return nil
            }
            images.append(UIImage(CGImage: imageRef, scale: UIScreen.mainScreen().scale, orientation: .Up))
        }
        if frameCount <= 1 {
            return images.first
        } else {
            return UIImage.animatedImageWithImages(images, duration: duration)
        }
    }
}
public enum WPCATransionStyle : String {
    case Fade = "kCATransitionFade"
    case MoveIn = "kCATransitionMoveIn"
    case Push = "kCATransitionPush"
    case Reveal = "kCATransitionReveal"
    case FromRight = "kCATransitionFromRight"
    case FromLeft = "kCATransitionFromLeft"
    case FromTop = "kCATransitionFromTop"
    case FromBottom = "kCATransitionFromBottom"
    case None = "None"
}
extension UIImageView {
    /**
     渐变设置图片第一种方法,tableview 上面有些卡顿
     
     - parameter newImage:
     - parameter duration:
     */
    func transitionWithImage(newImage:UIImage,duration:NSTimeInterval) {
        UIView.transitionWithView(self, duration: duration, options: UIViewAnimationOptions.TransitionCrossDissolve, animations: { () -> Void in
            self.image = newImage
            }) { (finish) -> Void in
                
        }
    }
    /**
     渐变设置图片第二种方法
     
     - parameter duration:
     */
    func addTransition(duration:NSTimeInterval,transionStyle:WPCATransionStyle = .Fade) {
        if self.layer.animationForKey(transionStyle.rawValue) == nil && transionStyle != .None {
            let transition = CATransition()
            transition.type = transionStyle.rawValue
            transition.duration = duration
            transition.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            self.layer.addAnimation(transition, forKey: transionStyle.rawValue)
        }
    }
    func removeTransition(transionStyle:WPCATransionStyle = .Fade) {
        if self.layer.animationForKey(transionStyle.rawValue) != nil {
            self.layer.removeAnimationForKey(transionStyle.rawValue)
        }
    }
    func wp_setImageWithAsset(urlString: String,placeholderImage: UIImage?) {
        self.tag = urlString.hash
        self.image = placeholderImage
        if WPCache.sharedInstance.defaultCache.objectForKey(urlString) != nil {
            self.image = WPCache.sharedInstance.defaultCache.objectForKey(urlString) as? UIImage
        } else {
            dispatch_async(dispatch_get_global_queue(0, 0), { () -> Void in
                let assetLib = ALAssetsLibrary()
                assetLib.assetForURL(NSURL(string: urlString), resultBlock: { (asset) -> Void in
                    let cgImg = asset.defaultRepresentation().fullScreenImage().takeUnretainedValue()
                    let fullImage = UIImage(CGImage: cgImg)
                    if self.tag == urlString.hash {
                        WPCache.sharedInstance.defaultCache.setObject(fullImage, forKey: urlString)
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.image = fullImage
                        })
                    }
                    }, failureBlock: { (error) -> Void in
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.image = placeholderImage
                        })
                })
            })
        }
    }
    func wp_setLoacalOrRemoteImageWith(urlString: String,withIsNotLocalPath remotePath:String,placeholderImage: UIImage?) {
        if urlString.hasPrefix("http") {
            self.wp_loadImageWithUrlString(NSURL(string: urlString)!, placeholderImage: placeholderImage)
        } else if urlString.hasPrefix("/var") {
            self.wp_setImageWithLocalPath(urlString, withIsNotLocalPath: remotePath,placeholderImage: placeholderImage)
        }
    }
    func wp_setPreviewImageWithLocalPath(localPath:String, withIsNotLocalPath remotePath:String) {
        self.tag = localPath.hashValue
        dispatch_async(dispatch_get_global_queue(0, 0), { () -> Void in
            if let image = UIImage(contentsOfFile: localPath) {
                if self.tag == localPath.hashValue {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.image = image
                    })
                }
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.wp_loadPreviewImageWithUrlString(NSURL(string: remotePath)!, placeholderImage: UIImage(named: "DefaultPortraitIcon"))
                })
            }
        })
    }
    /**
     异步加载本地图片
     
     - parameter localPath:
     - parameter remotePath:
     */
    func wp_setImageWithLocalPath(localPath:String, withIsNotLocalPath remotePath:String,placeholderImage: UIImage? = nil) {
        self.tag = localPath.hashValue
        dispatch_async(dispatch_get_global_queue(0, 0), { () -> Void in
            if let image = UIImage(contentsOfFile: localPath) {
                if self.tag == localPath.hashValue {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        self.image = image
                    })
                }
            } else {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.wp_loadImageWithUrlString(NSURL(string: remotePath)!, placeholderImage: UIImage(named: "DefaultPortraitIcon"))
                })
            }
        })
    }
    /**
     高效加圆角
     
     - parameter urlString:        url
     - parameter placeholderImage: 默认图
     */
    public func wp_roundImageWithURL(urlString:String,
        placeholderImage: UIImage?)
    {
        self.wp_setImageWithURLString(urlString, autoSetImage: false, placeholderImage: placeholderImage) { [weak self] (image) -> Void in
            self?.roundedImage(image)
        }
    }
    func roundedImage(downloadImage:UIImage,withRect rect:CGRect = CGRect(x: CGFloat.min, y: CGFloat.min, width: 80, height: 80),withRadius radius:CGFloat = 10.0,completion:((roundedImage:UIImage) -> Void)? = nil) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
            UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
            UIBezierPath(roundedRect: rect, cornerRadius: radius).addClip()
            downloadImage.drawInRect(rect)
            let roundedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.image = roundedImage
                if completion != nil {
                    completion!(roundedImage: roundedImage)
                }
            })
        }
    }
}
extension UIImageView {
    /**
     预览照片的异步加载方法
     
     - parameter url:
     - parameter placeholderImage:
     - parameter progressBlock:
     - parameter completionHandler:
     */
    func wp_loadPreviewImageWithUrlString(url: NSURL,
        placeholderImage: UIImage?,
        progressBlock:DownloadProgressBlock? = nil,
        completionHandler: CompletionHandler? = nil) {
            self.wp_loadImageWithUrlString(url, placeholderImage: placeholderImage, progressBlock: progressBlock, completionHandler: completionHandler)
    }
    /**
     图片异步加载封装方法
     
     - parameter url:               图片url
     - parameter placeholderImage:  默认图
     - parameter progressBlock:     进度回调
     - parameter completionHandler: 完成时回调
     */
    func wp_loadImageWithUrlString(url: NSURL,
        placeholderImage: UIImage?,
        progressBlock:DownloadProgressBlock? = nil,
        completionHandler: CompletionHandler? = nil) {
            self.wp_setImageWithURLString(url.absoluteString, autoSetImage: true, placeholderImage: placeholderImage) { (image) -> Void in
            }
    }
    /**
     自定义的异步加载图片
     
     - parameter urlString:        url
     - parameter placeholderImage: 默认图
     */
    func wp_setImageWithURLString(urlString: String,
        autoSetImage:Bool = true,
        withTransformStyle transformStyle:WPCATransionStyle = .Fade,
        duration:NSTimeInterval = 1.0,
        placeholderImage: UIImage? = UIColor.imageWithColor(UIColor.randomColor()),
        completionHandler:((image:UIImage) ->Void)? = nil) {
            guard urlString != "" else {
                self.image = placeholderImage
                return
            }
            if self.tag != urlString.hash {
                //解决reloaddata的时候imageview 闪烁问题
                self.tag = urlString.hash
                self.image = placeholderImage
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                if WPCache.imageExistWithKey(urlString) {
                    WPCache.getDiskCacheObjectForKey(urlString, withSuccessHandler: { (image, key, filePath) -> Void in
                        if self.tag == urlString.hash {
                            if autoSetImage {
                                if filePath == "" {
                                    //内存中取出
                                    self.removeTransition()
                                    self.image = image
                                } else {
                                    //硬盘中取出
                                    switch transformStyle {
                                    case .None:
                                        self.removeTransition()
                                        self.image = image
                                    case .Fade:
                                        self.addTransition(duration)
                                        self.image = image
                                    default:
                                        self.removeTransition()
                                        self.image = image
                                    }
                                }
                                if completionHandler != nil {
                                    completionHandler!(image: image)
                                }
                            } else {
                                if completionHandler != nil {
                                    completionHandler!(image: image)
                                }
                            }
                        }
                    })
                } else {
                    if urlString.length() <= 0 {
                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                            self.image = placeholderImage
                        })
                    } else {
                        WPWebImage.downloadImage(urlString, withSuccessColsure: { (image, imageData,saveUrl) -> Void in
                            dispatch_async(dispatch_get_global_queue(0, 0), { () -> Void in
                                let newImage = WPWebImage.wp_animatedImageWithGIFData(gifData: imageData)
                                if self.tag == urlString.hash {
                                    if autoSetImage {
                                        dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                            switch transformStyle {
                                            case .Fade:
                                                self.addTransition(duration)
                                                self.image = newImage
                                            default:
                                                self.removeTransition()
                                                self.image = newImage
                                            }
                                        })
                                    }
                                    WPCache.setDiskCacheObject(imageData, ForKey: urlString, withSuccessHandler: { (image, key, filePath) -> Void in
                                        if completionHandler != nil {
                                            completionHandler!(image: image)
                                        }
                                    })
                                }
                            })
                        })
                    }
                }
            }
    }
}