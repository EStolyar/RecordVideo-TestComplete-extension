﻿// Settings
var presetNormal = {
  name: "Normal",
  fps: 24,
  quality: 1000
};
var presetLow = {
  name: "Low",
  fps: 20,
  quality: 500
};
var presetHigh = {
  name: "High",
  fps: 30,
  quality: 1600
};
var presetDefault = presetNormal;

// Log messages
var logMessages = {
  noRecorder: {
    message: "Unable to record video. Please check that VLC video player is installed.",
    messageEx: "<p>You can download necessary VLC video player here:<br/><a href='%s' target='_blank'>%s</a></p>"
  },
  recStartOk: {
    message: "The video recording is started. You can find recorded video in Logs folder.",
    messageEx: "The quality is: %s.\r\nYou can change the quality of videos by redefining VideoQuality parameter.\r\n\r\nThe video file will be created:\r\n%s"
  },
  recStartFail: {
    message: "The video is already in recording state. Please see Additional information.",
    messageEx: "You need to stop previous video recording before starting the new one.\r\nIf you see " + "%s" + ".exe process, please close it manually."
  },
  recStopOk: {
    message: "The video recording is stopped.",
    messageEx: "The video file has been created:\r\n%s"
  },
  recStopFail: {
    message: "The video recording was not even started!",
    messageEx: "Unable to detect working instance of VLC application. Please, check that you start recording in your test."
  },
  recStopFailNotStarted: {
    message: "The video recording was not even started! Please see Additional information.",
    messageEx: "It seems the previos instance of VLC player was not closed.\r\nIf you see %s.exe process, please close it manually."
  },
  recUnexpectedError: {
    message: "Something was wrong during the recording process. Please see Additional Information.",
    messageEx: "Please try to launch the player manually with command line:\r\n\r\n\"%s\" %s"
  },
  recWasTerminated: {
    message: "The player process was terminated forcely because of timeout for video encoding.",
    messageEx: "Please try to record smaller video."
  }
};

//Other messages
var messages = {
  encodingInProgress: "Encoding the video file...",
  startDescription: "Start video recording. You can find recorded video in Logs folder.",
  stopDescription: "Stop video recording. You can find recorded video in Logs folder."
};

//Recorder information
function RecorderInfo() {
  this.getHomepage = function () {
    return "https://www.videolan.org/";
  };

  this.getProcessName = function () {
    return "vlc";
  };

  function getRegistryValue(name, defaultValue) {
    var bitPrefix = Sys.OSInfo.Windows64bit ? "Wow6432Node\\" : "";
    var path = aqString.Format("HKEY_LOCAL_MACHINE\\SOFTWARE\\%s%s", bitPrefix, name);
    var result = defaultValue;

    try {
      result = WshShell.RegRead(path);
    }
    catch (ignore) {
    }
    return result;
  }

  this.isIstalled = function () {
    return getRegistryValue("VideoLan\\", "novalue") !== "novalue";
  };

  this.getPath = function () {
    return getRegistryValue("VideoLAN\\VLC\\InstallDir") + "\\" + this.getProcessName() + ".exe";
  };
}

//Video file information
function VideoFile() {
  var _path = (function generateVideoFilePath() {
    var now = aqDateTime.Now();

    var year = aqDateTime.GetYear(now);
    var month = aqDateTime.GetMonth(now);
    var day = aqDateTime.GetDay(now);
    var hour = aqDateTime.GetHours(now);
    var minute = aqDateTime.GetMinutes(now);
    var sec = aqDateTime.GetSeconds(now);

    return Log.Path + "video_" + [year, month, day, hour, minute, sec].join("-") + ".mp4";
  })();

  this.getPath = function () {
    return _path;
  };
}

//Cursor file information
function CursorFile() {
  var _format = "png";
  var _path = aqFileSystem.ExpandUNCFileName("%temp%\\vlc_cursor." + _format);

  if (!aqFile.Exists(_path)) {
    (function createCursorFile(size, color, format, path) {
      var picture = Sys.Desktop.Picture(0, 0, size, size);
      var config = picture.CreatePictureConfiguration(format);
      var i, j;

      config.CompressionLevel = 9;
      for (i = 0; i < size; i++) {
        for (j = 0; j < size; j++) {
          picture.Pixels(i, j) = color;
        }
      }

      picture.SaveToFile(path, config);
    })(12, 0x0000FF/*red*/, _format, _path);
  }

  this.getPath = function () {
    return _path;
  };
}

// Engine
function RecorderEngine() {
  var _recorderInfo = new RecorderInfo();

  var _settings = presetDefault;
  var _videoFile;
  var _cursorFile;
  var _isStarted = false;

  function runCommand(args) {
    WshShell.Run(aqString.Format('"%s" %s', _runnerInfo.getPath(), args), 2, false);
  }

  function getStartCommandArgs() {
    return "--one-instance screen:// -I dummy :screen-fps=" + _settings.fps +
      " :screen-follow-mouse :screen-mouse-image=" + "\"" + _cursorFile.getPath() + "\"" +
      " :no-sound :sout=#transcode{vcodec=h264,vb=" + _settings.quality + ",fps=" + _settings.fps + ",scale=1}" +
      " :std{access=file,dst=\"" + file + "\"}";
  }

  function runStartCommand() {
    runCommand(getStartCommandArgs());
  }

  function runStopCommand() {
    runCommand("--one-instance vlc://quit");
  }

  function ensureRecorderProcessIsClosed(timeout) {
    var timeoutPortion = 1000;
    var process = Sys.WaitProcess(_recorderInfo.getProcessName());
    var wastedTime = 0;
    while (process.Exists) {
      Delay(timeoutPortion, messages.encodingInProgress);
      wastedTime += timeoutPortion;
      if (wastedTime >= timeout) {
        process.Terminate();
        Log.Warning(logMessages.recWasTerminated.message, logMessages.recWasTerminated.messageEx);
      }
    }
  }

  this.start = function (settings) {
    var recExists;

    Indicator.Hide();
    recExists = Sys.WaitProcess(_recorderInfo.getProcessName()).Exists;
    Indicator.Show();

    if (recExists) {
      Log.Warning(logMessages.recStartFail.message, aqString.Format(logMessages.recStartFail.messageEx, _recorderInfo.getProcessName()));
      return;
    }

    if (!_recorderInfo.isInstalled()) {
      var pmHigher = 300;
      var attr = Log.CreateNewAttributes();
      attr.ExtendedMessageAsPlainText = false;
      Log.Warning(logMessages.noRecorder.message, aqString.Format(logMessages.noRecorder.messageEx, _recorderInfo.homepage, _recorderInfo.homepage), pmHigher, attr);
      return;
    }

    _settings = settings;
    _videoFile = new VideoFile();
    _cursorFile = new CursorFile();
    _isStarted = true;
    runStartCommand();

    Log.Message(logMessages.recStartOk.message, aqString.Format(logMessages.recStartOk.messageEx, _settings.name, _videoFile.getPath()));
    return _videoFile.getPath();
  };

  this.stop = function () {
    var recExists, i;

    Indicator.Hide();
    recExists = Sys.WaitProcess(_recorderInfo.getProcessName(), timeout_minimum).Exists;
    Indicator.Show();

    if (!recExists) {
      Log.Warning(logMessages.recStopFail.message, logMessages.recStopFail.messageEx);
      return;
    }

    if (!_isStarted) {
      Log.Warning(logMessages.recStopFailNotStarted.message, aqString.Format(logMessages.recStopFailNotStarted.messageEx, _recorderInfo.getProcessName()));
      return;
    }

    Indicator.Hide();
    Delay(2000); // 2 sec. delay to catch the last moments
    runStopCommand();
    Delay(1000); // 1 sec. delay to avoid encoding status in video
    Indicator.Show();
    Indicator.PushText(messages.encodingInProgress);

    // forcely close player after timeout of video encoding
    Log.Enabled = false;
    ensureRecorderProcessIsClosed(10 * 60 * 1000 /*wait 10 minutes for player encode the video file*/);
    Log.Enabled = true;

    _isStarted = false;
    for (i = 0; i < 20; i++) {
      if (aqFile.Exists(_videoFile.getPath())) {
        break;
      }
      Delay(1000, messages.encodingInProgress);
    }

    if (aqFile.Exists(_videoFile.getPath())) {
      Log.Link(_videoFilePath, logMessages.recStopOk.message, aqString.Format(logMessages.recStopOk.messageEx, _videoFile.getPath()));
    }
    else {
      Log.Warning(logMessages.recUnexpectedError.message, aqString.Format(logMessages.recUnexpectedError.messageEx, _recorderInfo.getProcessName(), _recorderInfo.getPath(), getStartCommandArgs()));
    }
    return _videoFile.getPath();
  };

  this.onInitialize = function () {
  };

  this.onFinalize = function () {
    if (_isStarted) {
      runStopCommand();
    }
  };
}

var recorderEngine = new RecorderEngine();



// Do on extension load
function Initialize() {
  recorderEngine.onInitialize();
}

// Do on extension unload
function Finalize() {
  recorderEngine.onFinalize();
}

//
// KDT Start
//
function StartRecording_OnCreate(Data, Parameters) {
  Parameters.VideoQuality = presetDefault.name;
}

function StartRecording_GetDescription(Data) {
  return messages.startDescription;
}

function StartRecording_OnExecute(Data, VideoQuality) {
  var presets = [presetNormal, presetLow, presetHigh];
  var i, found = presetDefault;

  for (i = 0; i < presets.lenght; i++) {
    if (presets[i].name.toLowerCase() === VideoQuality.toLowerCase()) {
      found = presets[i];
      break;
    }
  }
  return recorderEngine.start(found);
}

function StartRecording_OnSetup(Data, Parameters) {
  return true;
}

//
// KDT Stop
//

function StopRecording_OnCreate(Data, Parameters) {
  return true;
}

function StopRecording_GetDescription(Data) {
  return messages.stopDescription;
}

function StopRecording_OnExecute(Data, Parameters) {
  return recorderEngine.stop();
}

function StopRecording_OnSetup(Data, Parameters) {
  return true;
}