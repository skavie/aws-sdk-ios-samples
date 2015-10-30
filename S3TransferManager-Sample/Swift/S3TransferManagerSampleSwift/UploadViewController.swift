/*
* Copyright 2010-2015 Amazon.com, Inc. or its affiliates. All Rights Reserved.
*
* Licensed under the Apache License, Version 2.0 (the "License").
* You may not use this file except in compliance with the License.
* A copy of the License is located at
*
*  http://aws.amazon.com/apache2.0
*
* or in the "license" file accompanying this file. This file is distributed
* on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
* express or implied. See the License for the specific language governing
* permissions and limitations under the License.
*/

import UIKit
import AssetsLibrary

class UploadViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource, ELCImagePickerControllerDelegate {

    @IBOutlet weak var collectionView: UICollectionView!

    var uploadRequests = Array<AWSS3TransferManagerUploadRequest?>()
    var uploadFileURLs = Array<NSURL?>()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tmpDirURL = NSURL.fileURLWithPath(NSTemporaryDirectory(), isDirectory: true)
        
        //let fileURL = tmpDirURL.URLByAppendingPathComponent("pkm").URLByAppendingPathExtension("jpg")
        //print("FilePath: \(fileURL.path)")
        
        
        //let writePath = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("upload")
        let writePath = tmpDirURL
        
        do {
            try NSFileManager.defaultManager().createDirectoryAtPath(writePath.path!, withIntermediateDirectories: true, attributes: nil)
        }
        catch let error as NSError {
            NSLog("\(error.localizedDescription)")
        }
    }

    @IBAction func showAlertController(barButtonItem: UIBarButtonItem) {
        let alertController = UIAlertController(
            title: "Available Actions",
            message: "Choose your action.",
            preferredStyle: .ActionSheet)

        let selectPictureAction = UIAlertAction(
            title: "Select Pictures",
            style: .Default) { (action) -> Void in
                self.selectPictures()
        }
        alertController.addAction(selectPictureAction)

        let cancelAllUploadsAction = UIAlertAction(
            title: "Cancel All Uploads",
            style: .Default) { (action) -> Void in
                self.cancelAllUploads()
        }
        alertController.addAction(cancelAllUploadsAction)

        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .Cancel) { (action) -> Void in }
        alertController.addAction(cancelAction)

        self.presentViewController(
            alertController,
            animated: true) { () -> Void in }
    }

    func selectPictures() {
        let imagePickerController = ELCImagePickerController()
        imagePickerController.maximumImagesCount = 20
        imagePickerController.imagePickerDelegate = self

        self.presentViewController(
            imagePickerController,
            animated: true) { () -> Void in }
    }

    func upload(uploadRequest: AWSS3TransferManagerUploadRequest) {
        let transferManager = AWSS3TransferManager.defaultS3TransferManager()

        transferManager.upload(uploadRequest).continueWithBlock { (task) -> AnyObject! in
            if let error = task.error {
                if error.domain == AWSS3TransferManagerErrorDomain as String {
                    if let errorCode = AWSS3TransferManagerErrorType(rawValue: error.code) {
                        switch (errorCode) {
                        case .Cancelled, .Paused:
                            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                                self.collectionView.reloadData()
                            })
                            break;

                        default:
                            print("upload() failed: [\(error)]")
                            break;
                        }
                    } else {
                        print("upload() failed: [\(error)]")
                    }
                } else {
                    print("upload() failed: [\(error)]")
                }
            }

            if let exception = task.exception {
                print("upload() failed: [\(exception)]")
            }

            if task.result != nil {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    if let index = self.indexOfUploadRequest(self.uploadRequests, uploadRequest: uploadRequest) {
                        self.uploadRequests[index] = nil
                        self.uploadFileURLs[index] = uploadRequest.body

                        let indexPath = NSIndexPath(forRow: index, inSection: 0)
                        self.collectionView.reloadItemsAtIndexPaths([indexPath])
                    }
                })
            }
            return nil
        }
    }

    func cancelAllUploads() {
        for (_, uploadRequest) in self.uploadRequests.enumerate() {
            if let uploadRequest = uploadRequest {
                uploadRequest.cancel().continueWithBlock({ (task) -> AnyObject! in
                    if let error = task.error {
                        print("cancel() failed: [\(error)]")
                    }
                    if let exception = task.exception {
                        print("cancel() failed: [\(exception)]")
                    }
                    return nil
                })
            }
        }
    }

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.uploadRequests.count
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(
            "UploadCollectionViewCell",
            forIndexPath: indexPath) as! UploadCollectionViewCell

        if let uploadRequest = self.uploadRequests[indexPath.row] {
            switch uploadRequest.state {
            case .Running:
                if let data = NSData(contentsOfURL: uploadRequest.body) {
                    cell.imageView.image = UIImage(data: data)
                    cell.label.hidden = true
                }

                uploadRequest.uploadProgress = { (bytesSent, totalBytesSent, totalBytesExpectedToSend) -> Void in
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        if totalBytesExpectedToSend > 0 {
                            cell.progressView.progress = Float(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
                        }
                    })
                }

                break;

            case .Canceling:
                cell.imageView.image = nil
                cell.label.hidden = false
                cell.label.text = "Cancelled"
                break;

            case .Paused:
                cell.imageView.image = nil
                cell.label.hidden = false
                cell.label.text = "Paused"
                break;

            default:
                cell.imageView.image = nil
                cell.label.hidden = true
                break;
            }
        }

        if let downloadFileURL = self.uploadFileURLs[indexPath.row] {
            if let data = NSData(contentsOfURL: downloadFileURL) {
                cell.imageView.image = UIImage(data: data)
                cell.label.hidden = false
                cell.label.text = "Uploaded"
                cell.progressView.progress = 1.0
            }
        }

        return cell
    }

    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        collectionView.deselectItemAtIndexPath(indexPath, animated: true)

        if let uploadRequest = self.uploadRequests[indexPath.row] {
            switch uploadRequest.state {
            case .Running:
                uploadRequest.pause().continueWithBlock({ (task) -> AnyObject! in
                    if let error = task.error {
                        print("pause() failed: [\(error)]")
                    }
                    if let exception = task.exception {
                        print("pause() failed: [\(exception)]")
                    }

                    return nil
                })
                break

            case .Paused:
                self.upload(uploadRequest)
                collectionView.reloadItemsAtIndexPaths([indexPath])
                break

            default:
                break
            }
        }
    }

    func elcImagePickerController(picker: ELCImagePickerController!, didFinishPickingMediaWithInfo info: [AnyObject]!) {
        self.dismissViewControllerAnimated(true, completion: nil)

        for (_, imageDictionary) in info.enumerate() {
            if let imageDictionary = imageDictionary as? Dictionary<String, AnyObject> {
                if let mediaType = imageDictionary[UIImagePickerControllerMediaType] as? String {
                    if mediaType == ALAssetTypePhoto {
                        if let image = imageDictionary[UIImagePickerControllerOriginalImage] as? UIImage {
                            let fileName = NSProcessInfo.processInfo().globallyUniqueString.stringByAppendingString(".png")
                            //let fileName = "test.png"
                            //let filePath = NSURL(fileURLWithPath: NSTemporaryDirectory()).URLByAppendingPathComponent("upload").URLByAppendingPathComponent(fileName)
                            
                            let tmpDirURL = NSURL.fileURLWithPath(NSTemporaryDirectory(), isDirectory: true)
                            let filePath = tmpDirURL.URLByAppendingPathComponent(fileName, isDirectory: false)

                            //print("Filename generated: \(fileName)")
                            //print("Filepath generated: \(filePath.path!)")
                            
                            let imageData = UIImagePNGRepresentation(image)
                            
                            imageData!.writeToFile(String(filePath), atomically: true)
                            
                            do {
                                try imageData!.writeToFile(filePath.path!, options: NSDataWritingOptions.AtomicWrite)
                            }
                            catch let error as NSError {
                                NSLog("\(error.localizedDescription)")
                            }
                            
                            let uploadRequest = AWSS3TransferManagerUploadRequest()
                            uploadRequest.body = NSURL(fileURLWithPath: filePath.path!)
                            uploadRequest.key = fileName
                            uploadRequest.bucket = S3BucketName

                            self.uploadRequests.append(uploadRequest)
                            self.uploadFileURLs.append(nil)

                            self.upload(uploadRequest)
                        }
                    }
                }
            }
        }
        self.collectionView.reloadData()
    }

    func elcImagePickerControllerDidCancel(picker: ELCImagePickerController!) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }

    func indexOfUploadRequest(array: Array<AWSS3TransferManagerUploadRequest?>, uploadRequest: AWSS3TransferManagerUploadRequest?) -> Int? {
        for (index, object) in array.enumerate() {
            if object == uploadRequest {
                return index
            }
        }
        return nil
    }
}

class UploadCollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var label: UILabel!
}
