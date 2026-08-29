# Third-Party Notices

Slowlight 本身使用 [MIT License](LICENSE)。第三方依赖和内嵌组件仍分别遵循其自身许可证，项目级 MIT License 不替代这些许可证。

## desktop_multi_window

Slowlight 客户端包含一份本地维护的 `desktop_multi_window`，用于 Windows 多屏休息提醒的多窗口能力。

- License: Apache License 2.0
- License text: [`client/third_party/desktop_multi_window/LICENSE`](client/third_party/desktop_multi_window/LICENSE)

当前内嵌副本没有单独的 `NOTICE` 文件；发行时应继续保留上述 Apache-2.0 许可证文本及上游已有的版权/归属声明。

## Inno Setup Chinese Simplified Translation

Slowlight Windows 安装器构建使用 `kira-96/Inno-Setup-Chinese-Simplified-Translation` 提供的简体中文 Inno Setup 消息翻译。构建脚本固定到上游提交 `1ff90acc4ed4aee82b1cda43253243deee3daed4`，并校验对应 Git Blob `30d997321197c7c96d8e111e9ddd6c0ca8da5f09`。

- Upstream: `https://github.com/kira-96/Inno-Setup-Chinese-Simplified-Translation`
- License: MIT License
- Copyright: Copyright (c) 2019 - 2020 kirakira

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## 其它第三方依赖

Flutter / Dart、Go 与其余包管理器依赖仍保留各自上游许可证。发布二进制时如增加需要额外归属、NOTICE 或再分发文本的组件，应同步更新本文件或应用内统一的“开源许可证”页面。
