import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:global_repository/global_repository.dart';
import 'package:speed_share/pages/model/model.dart';
import 'package:speed_share/pages/video_preview.dart';
import 'package:speed_share/themes/theme.dart';
import 'package:path/path.dart';
import 'package:get/get.dart' hide Response;
import 'package:url_launcher/url_launcher.dart';

class FileItem extends StatefulWidget {
  final MessageFileInfo info;
  final bool sendByUser;
  final String roomUrl;

  const FileItem({
    Key key,
    this.info,
    this.sendByUser,
    this.roomUrl,
  }) : super(key: key);
  @override
  _FileItemState createState() => _FileItemState();
}

class _FileItemState extends State<FileItem> {
  MessageFileInfo info;
  final Dio dio = Dio();
  CancelToken cancelToken = CancelToken();
  int count = 0;
  double fileDownratio = 0.0;
  // 网速
  String speed = '0';
  Timer timer;
  Future<void> downloadFile(String urlPath, String savePath) async {
    print(urlPath);
    Response<String> response = await dio.head<String>(urlPath);
    final int fullByte = int.tryParse(
      response.headers.value('content-length'),
    ); //得到服务器文件返回的字节大小
    print('fullByte -> $fullByte');
    savePath = savePath + '/' + basename(urlPath);
    // print(savePath);
    computeNetSpeed();
    await dio.download(
      urlPath,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: (count, total) {
        this.count = count;
        final double process = count / total;
        // Log.e(process);
        fileDownratio = process;
        setState(() {});
      },
    );
    timer?.cancel();
  }

  Future<void> computeNetSpeed() async {
    int tmpCount = 0;
    timer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      int diff = count - tmpCount;
      tmpCount = count;
      Log.e('diff -> $diff');
      // 乘以2是因为半秒测的一次
      speed = FileSizeUtils.getFileSize(diff * 2);
      // *2 的原因是半秒测的一次
      Log.e('网速 -> $speed');
    });
  }

  @override
  void initState() {
    super.initState();
    info = widget.info;
  }

  @override
  void dispose() {
    cancelToken.cancel();
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String url;
    if (widget.sendByUser) {
      url = 'http://127.0.0.1:8002/' + widget.info.filePath;
    } else {
      url = widget.info.url + '/' + widget.info.filePath;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment:
          widget.sendByUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: accentColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildPreviewWidget(),
                if (!widget.sendByUser)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      SizedBox(
                        height: 8,
                      ),
                      ClipRRect(
                        borderRadius:
                            const BorderRadius.all(Radius.circular(25.0)),
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.black12,
                          valueColor: AlwaysStoppedAnimation(
                            fileDownratio == 1.0
                                ? Colors.lightGreen
                                : Colors.red,
                          ),
                          value: fileDownratio,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$speed/s',
                            style: TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                          Row(
                            children: [
                              SizedBox(
                                child: Text(
                                  '${FileSizeUtils.getFileSize(count)}',
                                  style: TextStyle(
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                              Text(
                                '/',
                                style: TextStyle(
                                  color: Colors.black54,
                                ),
                              ),
                              SizedBox(
                                child: Text(
                                  '${widget.info.fileSize}',
                                  style: TextStyle(
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (!widget.sendByUser)
          Material(
            color: Colors.transparent,
            child: Column(
              children: [
                InkWell(
                  onTap: () async {
                    if (GetPlatform.isWeb) {
                      await canLaunch(url)
                          ? await launch(url)
                          : throw 'Could not launch $url';
                      return;
                    }
                    if (GetPlatform.isDesktop) {
                      const confirmButtonText = 'Choose';
                      final directoryPath =
                          await FileSelectorPlatform.instance.getDirectoryPath(
                        confirmButtonText: confirmButtonText,
                      );
                      if (directoryPath == null) {
                        return;
                      }
                      downloadFile(url, directoryPath);
                    } else {
                      downloadFile(url, RuntimeEnvir.filesPath);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.file_download,
                      size: 18,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () async {
                    showToast('链接已复制');
                    await Clipboard.setData(ClipboardData(text: url));
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.content_copy,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  UniqueKey key = UniqueKey();
  Widget buildPreviewWidget() {
    if (widget.info is MessageImgInfo) {
      String url;
      if (widget.sendByUser) {
        url = 'http://127.0.0.1:8002/' + widget.info.filePath;
      } else {
        url = widget.info.url + '/' + widget.info.filePath;
      }
      return Hero(
        tag: key,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              Get.to(
                Material(
                  child: Hero(
                    tag: key,
                    child: Image.network(url),
                  ),
                ),
              );
            },
            child: Image.network(
              url,
              width: 200,
            ),
          ),
        ),
      );
    } else if (widget.info is MessageVideoInfo) {
      MessageVideoInfo info = widget.info;
      String url;
      if (widget.sendByUser) {
        url = 'http://127.0.0.1:8002/' + info.filePath;
      } else {
        url = info.url + '/' + info.filePath;
      }
      String thumbnailUrl;
      if (widget.sendByUser) {
        thumbnailUrl = 'http://127.0.0.1:8002/' + info.thumbnailPath;
      } else {
        thumbnailUrl = info.url + '/' + info.thumbnailPath;
      }
      return InkWell(
        onTap: () {
          NiNavigator.of(Get.context).pushVoid(
            Material(
              child: Hero(
                tag: key,
                child: SamplePlayer(
                  url: url,
                ),
              ),
            ),
          );
        },
        child: Hero(
          tag: key,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.network(thumbnailUrl),
              Icon(
                Icons.play_circle,
                color: accentColor,
                size: 48,
              )
            ],
          ),
        ),
      );
    }
    return Text(widget.info.fileName);
  }
}