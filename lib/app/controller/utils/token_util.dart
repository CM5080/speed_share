import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:global_repository/global_repository.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:speed_share/utils/chat_server_v2.dart';
import 'package:speed_share/utils/http/http.dart';
import 'package:speed_share/utils/shelf/static_handler.dart';

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;

import 'server_util.dart';

// Router fileRouter = Router();

/// 用来处理token请求的响应
/// 主要是为速享提供筛选IP地址的能力

void handleTokenCheck(int port) {
  // 用来为其他设备检测网络互通的方案
  // 其他设备会通过消息中的IP地址对 `/check_token` 发起 get 请求
  // 如果有响应说明胡互通
  fileRouter.get('/check_token', (shelf.Request request) {
    return shelf.Response.ok('success', headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': '*',
      'Access-Control-Allow-Methods': '*',
      'Access-Control-Allow-Credentials': 'true',
    });
  });

  io.serve(
    fileRouter,
    InternetAddress.anyIPv4,
    port,
    shared: true,
  );
}

// 发起http get请求，用来校验网络是否互通
// 如果不通，会返回null
Future<String> getToken(String url) async {
  Log.i('访问 $url/check_token 以检测网络是否互通');
  Completer lock = Completer();
  CancelToken cancelToken = CancelToken();
  Response response;
  Future.delayed(const Duration(milliseconds: 1000), () {
    if (!lock.isCompleted) {
      cancelToken.cancel();
    }
  });
  try {
    response = await httpInstance.get(
      '$url/check_token',
      cancelToken: cancelToken,
    );
    if (!lock.isCompleted) {
      lock.complete(response.data);
    }
    Log.i('/check_token 响应 ${response.data}');
  } catch (e) {
    if (!lock.isCompleted) {
      lock.complete(null);
    }
  }
  return await lock.future;
} // 得到正确的url

Future<String> getCorrectUrlWithAddressAndPort(
  List<String> addresses,
  int port,
) async {
  for (String address in addresses) {
    String token = await getToken('http://$address:$port');
    if (token != null) {
      return 'http://$address';
    }
  }
  return null;
}
