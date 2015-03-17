"use strict";

function positionGlowArrow() {
  var headLinks = document.getElementById("head-links");
  var activeLink = headLinks.getElementsByClassName("active")[0]
  if (activeLink == undefined || activeLink == null)
    return;
  
  var offset = (headLinks.offsetWidth - activeLink.offsetLeft) - (activeLink.offsetWidth / 2) - 133;
  var glowArrow = document.getElementById("glow-arrow");
  glowArrow.style.right = offset + "px";
}

window.onload = function() {
  positionGlowArrow();
};