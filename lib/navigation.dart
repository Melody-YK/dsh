/// 全局导航 key：供 Navigator 外层组件（如 RespondHandler）弹审批/提问。
library;

import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
