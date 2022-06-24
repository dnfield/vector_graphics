// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Don't skip rasterization on web platform debug mode.
// TODO: determine how this will be enabled/disabled.
bool get debugSkipRaster {
  return false;
}

/// A debug only override for controlling the value of [debugRunningOnTester].
bool? debugRunningOnTesterOverride;

/// Whether this code is being executed in the flutter tester.
bool get debugRunningOnTester {
  return debugRunningOnTesterOverride ?? false;
}
