import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:file_manager/file_manager.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:global_repository/global_repository.dart';
import 'package:speed_share/config/config.dart';
import 'package:speed_share/themes/default_theme_data.dart';
import 'package:speed_share/utils/chat_server.dart';
import 'package:speed_share/utils/http/http.dart';
import 'package:speed_share/utils/shelf_static.dart';
import 'package:video_compress/video_compress.dart';

import 'item/message_item.dart';
import 'model/model.dart';
import 'model/model_factory.dart';

extension IpString on String {
  bool isSameSegment(String other) {
    final List<String> serverAddressList = split('.');
    final List<String> localAddressList = other.split('.');
    if (serverAddressList[0] == localAddressList[0] &&
        serverAddressList[1] == localAddressList[1] &&
        serverAddressList[2] == localAddressList[2]) {
      // 默认为前三个ip段相同代表在同一个局域网，可能更复杂，涉及到网关之类的，由这学期学的计算机网路来看
      return true;
    }
    return false;
  }
}

class ShareChat extends StatefulWidget {
  const ShareChat({
    Key key,
    this.needCreateChatServer = true,
    this.chatServerAddress,
  }) : super(key: key);

  /// 为`true`的时候，会创建一个聊天服务器，如果为`false`，则代表加入已有的聊天
  final bool needCreateChatServer;
  final String chatServerAddress;
  @override
  _ShareChatState createState() => _ShareChatState();
}

class _ShareChatState extends State<ShareChat> {
  FocusNode focusNode = FocusNode();
  TextEditingController controller = TextEditingController();
  GetSocket socket;
  List<Widget> children = [];
  ScrollController scrollController = ScrollController();
  bool isConnect = false;
  String chatRoomUrl = '';
  @override
  void initState() {
    super.initState();
    initChat();
  }

  @override
  void dispose() {
    if (isConnect) {
      socket.close();
    }
    focusNode.dispose();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        shadowColor: accentColor,
        title: Text('文件共享'),
      ),
      body: GestureDetector(
        onTap: () {
          focusNode.unfocus();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(
                  vertical: 8,
                ),
                controller: scrollController,
                itemCount: children.length,
                cacheExtent: 99999,
                itemBuilder: (c, i) {
                  return children[i];
                },
              ),
            ),
            sendMsgContainer(context),
          ],
        ),
      ),
    );
  }

  Material sendMsgContainer(BuildContext context) {
    return Material(
      color: Theme.of(context).appBarTheme.color,
      child: Container(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: Transform(
                  transform: Matrix4.identity()..translate(0.0, -4.0),
                  child: IconButton(
                    alignment: Alignment.center,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.file_copy,
                      color: accentColor,
                    ),
                    onPressed: () async {
                      if (GetPlatform.isAndroid) {
                        sendForAndroid();
                      }
                      if (GetPlatform.isDesktop) {
                        sendForDesktop();
                      }
                    },
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: focusNode,
                      controller: controller,
                      autofocus: false,
                      style: TextStyle(
                        textBaseline: TextBaseline.ideographic,
                      ),
                      onSubmitted: (_) {
                        sendTextMsg();
                        Future.delayed(Duration(milliseconds: 100), () {
                          focusNode.requestFocus();
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 16,
                  ),
                  Material(
                    color: Color(0xffcfbff7),
                    borderRadius: BorderRadius.circular(32),
                    borderOnForeground: true,
                    child: IconButton(
                      icon: Icon(
                        Icons.send,
                        color: Color(0xffede8f8),
                      ),
                      onPressed: () {
                        sendTextMsg();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> sendForDesktop() async {
    final typeGroup = XTypeGroup(
      label: 'images',
    );
    final files = await FileSelectorPlatform.instance
        .openFiles(acceptedTypeGroups: [typeGroup]);
    if (files.isEmpty) {
      return;
    }
    for (XFile xFile in files) {
      final file = xFile;
      String filePath = file.path;
      File thumbnailFile;
      String msgType = '';
      Log.e(filePath);
      // return;
      if (filePath.isVideoFileName || filePath.endsWith('.mkv')) {
        msgType = 'video';
        thumbnailFile = await VideoCompress.getFileThumbnail(
          filePath,
          quality: 50,
          position: -1,
        );
      } else if (filePath.isImageFileName) {
        msgType = 'img';
      } else {
        msgType = 'other';
      }
      print('msgType $msgType');
      int size = await File(filePath).length();

      filePath = filePath.replaceAll(RegExp('^[A-Z]:\\\\'), '');
      String fileUrl = '';
      List<String> address = await PlatformUtil.localAddress();
      for (String addr in address) {
        fileUrl += 'http://' + addr + ':8002 ';
      }
      fileUrl = fileUrl.trim();
      MessageBaseInfo info = MessageInfoFactory.fromJson({
        'filePath': filePath,
        'msgType': msgType,
        'thumbnailPath': thumbnailFile?.path?.replaceAll(
          '/storage/emulated/0/',
          '',
        ),
        'fileName': p.basename(filePath),
        'fileSize': FileSizeUtils.getFileSize(size),
        'url': fileUrl,
      });
      Log.w(await PlatformUtil.localAddress());
      // 发送消息
      socket.send(info.toString());
      // 将消息添加到本地列表
      children.add(messageItem(
        info,
        true,
      ));
      scroll();
      setState(() {});
    }
  }

  Future<void> sendForAndroid() async {
    // 选择文件路径
    String filePath = await FileManager.chooseFile(
      context: context,
      pickPath: '/storage/emulated/0',
    );
    print(filePath);
    if (filePath == null) {
      return;
    }
    String path = filePath.replaceAll(
      '/storage/emulated/0/',
      '',
    );
    print(path);
    File thumbnailFile;
    String msgType = '';
    if (filePath.isVideoFileName || filePath.endsWith('.mkv')) {
      msgType = 'video';
      thumbnailFile = await VideoCompress.getFileThumbnail(
        filePath,
        quality: 50,
        position: -1,
      );
    } else if (filePath.isImageFileName) {
      msgType = 'img';
    } else {
      msgType = 'other';
    }
    print('msgType $msgType');
    int size = await File(filePath).length();
    String fileUrl = chatRoomUrl;

    fileUrl = 'http://' +
        (await PlatformUtil.localAddress())[0] +
        ':${Config.shelfPort}';
    dynamic info = MessageInfoFactory.fromJson({
      'filePath': path,
      'msgType': msgType,
      'thumbnailPath': thumbnailFile?.path?.replaceAll(
        '/storage/emulated/0/',
        '',
      ),
      'fileName': p.basename(filePath),
      'fileSize': FileSizeUtils.getFileSize(size),
      'url': fileUrl,
    });
    // 发送消息
    socket.send(info.toString());
    // 将消息添加到本地列表
    children.add(messageItem(
      info,
      true,
    ));
    scroll();
    setState(() {});
  }

  Future<void> initChat() async {
    if (widget.needCreateChatServer) {
      // 是创建房间的一端
      createChatServer();
      chatRoomUrl = 'http://127.0.0.1:${Config.chatPort}';
    } else {
      chatRoomUrl = widget.chatServerAddress;
    }
    socket = GetSocket(chatRoomUrl + '/chat');
    Log.v('chat open');
    socket.onOpen(() {
      Log.d('chat连接成功');
      isConnect = true;
      getHistoryMsg();
    });
    try {
      await socket.connect();
      await Future.delayed(Duration.zero);
    } catch (e) {
      isConnect = false;
    }
    // 监听消息
    listenMessage();
    if (!isConnect && !GetPlatform.isWeb) {
      // 如果连接失败并且不是 web 平台
      children.add(messageItem(
        MessageTextInfo(content: '加入失败!'),
        false,
      ));
      return;
    }
    if (widget.needCreateChatServer) {
      sendAddressAndQrCode();
    } else {
      children.add(messageItem(
        MessageTextInfo(content: '已加入$chatRoomUrl'),
        false,
      ));
    }
    if (!GetPlatform.isWeb) {
      // 开启文件部署
      ShelfStatic.start();
    }
    setState(() {});
  }

  Future<void> sendAddressAndQrCode() async {
    // 这个if的内容是创建房间的设备，会得到本机ip的消息
    children.add(messageItem(
      MessageTextInfo(
        content: '当前窗口可通过以下url加入，也可以使用浏览器(推荐chrome)直接打开以下url，'
            '只有同局域网下的设备能打开喔~',
      ),
      false,
    ));
    List<String> addreses = await PlatformUtil.localAddress();
    if (addreses.isEmpty) {
      children.add(messageItem(
        MessageTextInfo(content: '未发现局域网IP'),
        false,
      ));
    } else
      for (String address in addreses) {
        if (address.startsWith('10.')) {
          continue;
        }
        children.add(messageItem(
          MessageTextInfo(content: 'http://$address:${Config.chatPort}'),
          false,
        ));
        children.add(messageItem(
          MessageQrInfo(content: 'http://$address:${Config.chatPort}'),
          false,
        ));
      }
  }

  void listenMessage() {
    socket.onMessage((message) async {
      // print('服务端的消息 - $message');
      if (message == '') {
        // 发来的空字符串就没必要解析了
        return;
      }
      Map<String, dynamic> map;
      try {
        map = jsonDecode(message);
      } catch (e) {
        return;
      }
      MessageBaseInfo messageInfo = MessageInfoFactory.fromJson(map);
      if (messageInfo is MessageFileInfo) {
        // for (String url in messageInfo.url.split(' ')) {
        //   Uri uri = Uri.parse(url);
        //   Log.d('${uri.scheme}://${uri.host}:7001');
        //   Response response;
        //   try {
        //     response = await httpInstance.get(
        //       '${uri.scheme}://${uri.host}:7001',
        //     );
        //     Log.w(response.data);
        //   } catch (e) {}
        //   if (response != null) {
        //     messageInfo.url = url;
        //   }
        // }
        for (String url in messageInfo.url.split(' ')) {
          Uri uri = Uri.parse(url);
          Log.v('消息带有的address -> ${uri.host}');
          for (String localAddr in await PlatformUtil.localAddress()) {
            if (uri.host.isSameSegment(localAddr)) {
              Log.d('其中消息的 -> ${uri.host} 与本地的$localAddr 在同一个局域网');
              messageInfo.url = url;
            }
          }
        }
      }
      children.add(messageItem(
        messageInfo,
        false,
      ));
      scroll();
      setState(() {});
    });
  }

  void getHistoryMsg() {
    // 这个消息来告诉聊天服务器，自己需要历史消息
    socket.send(jsonEncode({
      'type': "getHistory",
    }));
  }

  Future<void> scroll() async {
    // 让listview滚动
    await Future.delayed(Duration(milliseconds: 100));
    if (mounted) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: Duration(milliseconds: 100),
        curve: Curves.ease,
      );
    }
  }

  void sendTextMsg() {
    // 发送文本消息
    MessageTextInfo info = MessageTextInfo(
      content: controller.text,
      msgType: 'text',
    );
    socket.send(info.toString());
    children.add(messageItem(
      info,
      true,
    ));
    setState(() {});
    controller.clear();
    scroll();
  }
}
