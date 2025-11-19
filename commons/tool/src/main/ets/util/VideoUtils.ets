import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { media } from '@kit.MediaKit';
import { VideoSizeData } from '../model/VideoSizeData';
import { MP4Parser, ICallBack } from '@ohos/mp4parser';
import { promptAction } from '@kit.ArkUI';

class VideoUtils {
  private context = getContext(this) as common.UIAbilityContext;
  getLocalDirPath = this.context.cacheDir;
  videoDir = this.getLocalDirPath + '/videoDir';

  initializeFolder() {
    if (fs.accessSync(this.videoDir)) {
      fs.rmdirSync(this.videoDir);
    }
    fs.mkdirSync(this.videoDir)
  }

  async copyVideo(selectedVideoUri: string) {
    this.initializeFolder()
    let cacheVideoUri: string = fileUri.getUriFromPath(`${this.videoDir}/InputVideo.mp4`)
    // Copy the original video to the target directory
    await fs.copy(selectedVideoUri, cacheVideoUri);
  }

  async clipVideo(sTime: string, eTime: string, selectedVideoUri: string): Promise<boolean> {
    await this.copyVideo(selectedVideoUri)
    let isSuccess = false;
    await new Promise<void>((resolve, reject) => {
      // Based on the provided start and end times, the  video will be clipped
      MP4Parser.ffmpegCmd(`ffmpeg -y -i ${this.videoDir}/InputVideo.mp4 -ss ${sTime} -t ${eTime} -c copy ${this.videoDir}/OutputVideo.mp4`,
        {
          callBackResult: (code: number) => {
            if (code === 0) {
              isSuccess = true;
              resolve();
            } else {
              isSuccess = false;
              reject(new Error(`Clip video error,error code: ${code}`));
            }
          },
        }
      );
    });
    return isSuccess
  }

  // 保持原有的clipVideo方法兼容性，创建一个返回boolean的版本
  async clipVideoBoolean(sTime: string, dTime: string, selectedVideoUri: string): Promise<boolean> {
    const result = await this.clipVideo(sTime, dTime, selectedVideoUri);
    return result !== null;
  }

  async clipAndSaveVideo(sTime: string, dTime: string, selectedVideoUri: string): Promise<boolean> {
    let isSuccess = await this.clipVideoBoolean(sTime, dTime, selectedVideoUri)
    if (isSuccess) {
      try {
        let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
        // Specify the URI of the video located in the app sandbox to be saved to the media library
        let srcFileUri = fileUri.getUriFromPath(`${this.videoDir}/OutputVideo.mp4`);
        let srcFileUris: Array<string> = [
          srcFileUri
        ];
        // Specify the creation options for the video to be saved
        let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [
          {
            title: 'test', // 可选。
            fileNameExtension: 'mp4',
            photoType: photoAccessHelper.PhotoType.VIDEO,
            subtype: photoAccessHelper.PhotoSubtype.DEFAULT, // 可选。
          }
        ];
        let desFileUris: Array<string> =
          await phAccessHelper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
        let desFile: fs.File | undefined = undefined
        let srcFile: fs.File | undefined = undefined
        try {
          desFile = await fs.open(desFileUris[0], fs.OpenMode.WRITE_ONLY);
          srcFile = await fs.open(srcFileUri, fs.OpenMode.READ_ONLY);
          await fs.copyFile(srcFile.fd, desFile.fd);
        } finally {
          fs.closeSync(srcFile);
          fs.closeSync(desFile);
        }
        this.initializeFolder()
        return true;
      } catch (err) {
        return false;
      }
    } else {
      return false;
    }
  }

  // Obtain the video duration
  async getVideoDuration(selectedVideoUri: string): Promise<number> {
    let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(this.context);
    let predicates: dataSharePredicates.DataSharePredicates =
      new dataSharePredicates.DataSharePredicates();
    predicates.equalTo('uri', selectedVideoUri);
    let fetchOption: photoAccessHelper.FetchOptions = {
      fetchColumns: [photoAccessHelper.PhotoKeys.WIDTH, photoAccessHelper.PhotoKeys.HEIGHT,
        photoAccessHelper.PhotoKeys.TITLE, photoAccessHelper.PhotoKeys.SIZE,
        photoAccessHelper.PhotoKeys.DURATION],
      predicates: predicates
    };
    let fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
      await phAccessHelper.getAssets(fetchOption);
    const asset: photoAccessHelper.PhotoAsset = await fetchResult.getFirstObject();
    const rawDuration = asset.get(photoAccessHelper.PhotoKeys.DURATION);
    return Number(rawDuration);
  }

  // Format milliseconds into the specified format
  formatDuration(milliseconds: number): string {
    const totalSeconds = Math.floor(milliseconds / 1000);
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    return [hours, minutes, seconds]
      .map(v => v.toString().padStart(2, '0'))
      .join(':');
  }

  // Format seconds into the specified format
  formatDurationSecond(totalSeconds: number): string {
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;

    return [hours, minutes, seconds]
      .map(v => v.toString().padStart(2, '0'))
      .join(':');
  }

  // Obtain the width and height of the video
  async getVideoData(avFileDescriptor: media.AVFileDescriptor): Promise<VideoSizeData> {
    let videoSize: VideoSizeData = new VideoSizeData();
    let avMetaDataExtractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor();
    avMetaDataExtractor.fdSrc = avFileDescriptor;
    let metadata = await avMetaDataExtractor.fetchMetadata();
    videoSize.photoSize.width = parseInt(metadata.videoWidth as string);
    videoSize.photoSize.height = parseInt(metadata.videoHeight as string);
    if (metadata.duration) {
      videoSize.totalTime = parseInt(metadata.duration);
    }
    avMetaDataExtractor.release();
    return videoSize;
  }
}

export default new VideoUtils();