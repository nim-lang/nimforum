"use strict";

window.onload = function() {
  positionGlowArrow();
  processMainDates();
  window.setTimeout(performProcessingMainDates, 1000);
};

function performProcessingMainDates()
{
  if (processMainDates())
  {
    window.setTimeout(performProcessingMainDates, 1000);
  }
  else
  {
    window.setTimeout(performProcessingMainDates, 60000);
  }
}

function timeSince(date) {
    var result = ["", false];
    var seconds = Math.floor((new Date() - date) / 1000);

    var interval = Math.floor(seconds / 31536000);

    if (interval >= 1) {
        result[0] = interval + (interval == 1 ? " year ago" : " years ago");
        return result;
    }
    interval = Math.floor(seconds / 2592000);
    if (interval >= 1) {
        result[0] = interval + (interval == 1 ? " month ago" : " months ago");
        return result;
    }
    interval = Math.floor(seconds / 86400);
    if (interval >= 1) {
        result[0] = interval + (interval == 1 ? " day ago" : " days ago");
        return result;
    }
    interval = Math.floor(seconds / 3600);
    if (interval >= 1) {
        result[0] = interval + (interval == 1 ? " hour ago" : " hours ago");
        return result;
    }
    interval = Math.floor(seconds / 60);
    if (interval >= 1) {
        result[0] = interval + (interval == 1 ? " minute ago" : " minutes ago");
        return result;
    }
    if (seconds >= 1) {
      result[0] = Math.floor(seconds) +
          (seconds == 1 ? " second ago" : " seconds ago");
      result[1] = true;
      return result;
    }
    return ["less than a second ago", true];
}

function processMainDates() {
  var result = false;
  var threads = document.getElementById("talk-threads").children;
  for (var i = 0; i < threads.length; i++)
  {
    var activity = threads[i].getElementsByClassName("activity")[0];
    var activityDiv = activity.children[0];
    var isoDate = activityDiv.children[0].innerHTML;
    var parsed = Date.parse(isoDate);
    var timeS = timeSince(parsed);
    
    activityDiv.innerHTML = activityDiv.children[0].outerHTML +
        timeS[0];
    if (timeS[1]) { result = timeS[1] }
  }
  return result;
}
