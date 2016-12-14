#!/usr/bin/env bash
# vim: set ts=2 sw=2 sts=2 et fenc=utf-8 :
##########
# Copyright (c) 2016, TEL.RED LLC,
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
##########
# Usage:
#  $ curl https://${TELRED_REPOSITORY_BASE}/install.sh | sudo bash
# or,
#  $ wget https://${TELRED_REPOSITORY_BASE}/install.sh -O - | sudo bash
# whichever suits you best
##########

set -euo pipefail

TELRED_REPOSITORY_BASE='https://tel.red/repos'

function _detect_distribution() {
  if hash pacman 2>/dev/null ; then
    echo 'archlinux'

  elif hash emerge 2>/dev/null ; then
    echo 'gentoo'

  elif hash zypper 2>/dev/null; then
    echo 'suse'

  elif hash dnf 2>/dev/null; then
    echo 'fedora'

  elif hash yum 2>/dev/null; then
    echo 'redhat'

  elif hash apt-get 2>/dev/null; then
    echo 'debian'

  else
    echo -e "\e[1;31mFailed to determine package manager\e[0m" 2>&1
    exit -1  
  fi

  return 0
}

function _apt_install() {
  apt-get update
  apt-get -y install $@
}

function _apt_unininstall() {
  apt-get --purge autoclean $@
}

function _apt_add_repo() {
  # erase obsolete repository entries, if any
  sed -i '/https\?:\/\/.*\btel.red\b/d' /etc/apt/sources.list
  # Debian wheezy may lack these two
  _apt_install 'apt-transport-https' 'ca-certificates'
  
  hash lsb_release >/dev/null || ( _apt_install 'lsb-release' && _temp=( ${_temp[@]+"${_temp[@]}"} 'lsb-release' ) )
  
  echo deb "${TELRED_REPOSITORY_BASE}"/$(lsb_release -si | tr [:upper:] [:lower:]) $(lsb_release -sc | tr [:upper:] [:lower:]) non-free > /etc/apt/sources.list.d/telred.list

  sudo apt-key adv \
    --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 9454C19A66B920C83DDF696E07C8CCAFCE49F8C5
}

function _dnf_install() {
  dnf --assumeyes install $@
}

function _dnf_uninstall() {
  dnf --assumeyes remove $@
}

function _dnf_add_repo() {
  declare -i _fc_release=$( rpm -E '%{dist}' | tr -c -d [:digit:] )
  dnf --assumeyes install "${TELRED_REPOSITORY_BASE}/fedora/${_fc_release}/noarch/telred-fedora-${_fc_release}-latest.fc${_fc_release}.noarch.rpm"
}

function _yum_install() {
  yum -y install $@
}

function _yum_uninstall() {
  yum -y remove $@
}

function _yum_add_repo() {
  # .dist rpm macro is not present OOB on RHEL/CentOS 5
  declare -i _release=$( rpm -qf $(which rpm) | cut -d'.' -f4 | tr -c -d [:digit:] )
  local _repo_rpm="${TELRED_REPOSITORY_BASE}/redhat/${_release}/noarch/telred-redhat-${_release}-latest.el${_release}.noarch.rpm"

  if (( ${_release} > 5 )) ; then
    yum --assumeyes install "${_repo_rpm}" || true

  else
    hash wget 2>/dev/null || ( eval ${_install} 'wget' && _temp=( ${_temp[@]+"${_temp[@]}"} 'wget' ) )
      
    local _tmpdir=$( mktemp -d )

    wget --no-check-certificate "${_repo_rpm}" -O "${_tmpdir}/repo.rpm"
    yum -y localinstall --nogpgcheck "${_tmpdir}/repo.rpm"

    rm -fr ${_tmpdir}
  fi
  echo "TEMP RPMs: ${_temp[@]-}"
}

function _zypper_install() {
  local package=$1
  zypper --non-interactive --gpg-auto-import-keys install $1
}

function _zypper_uninstall() {
  zypper --non-interactive remove $@
}

function _zypper_add_repo() {
  hash lsb_release 2>/dev/null || ( eval ${_install} 'lsb-release' && _temp=( ${_temp[@]+"${_temp[@]}"} 'lsb-release' ) )

  local _suse_release=$( lsb_release -sr )

  local _suse_flavour
  if lsb_release -sd | grep 'Enterprise' >/dev/null ; then
    _flavour='suse'
    _suse_release=${_suse_release%%.*}
  else
    _flavour='opensuse'
  fi

  zypper removerepo 'telred-suse' || true
  zypper addrepo --refresh "${TELRED_REPOSITORY_BASE}/${_flavour}/${_suse_release}/" "telred-${_flavour}-${_suse_release}"
}

function run() {
  local _install
  local _add_repo
  local _temp=()

  case $(_detect_distribution) in
    suse)
      _install='_zypper_install'
      _uninstall='_zypper_uninstall'
      _add_repo='_zypper_add_repo'
      ;;

    fedora)
      _install='_dnf_install'
      _uninstall='_dnf_uninstall'
      _add_repo='_dnf_add_repo'
      ;;

    redhat)
      _install='_yum_install'
      _uninstall='_yum_uninstall'
      _add_repo='_yum_add_repo'
      ;;

    debian)
      _install='_apt_install'
      _uninstall='_apt_uninstall'
      _add_repo='_apt_add_repo'
      ;;

    archlinux)
      ;;

    gentoo)
      ;;
  esac;
  
  eval ${_add_repo}
  eval ${_install} sky
  (( ${#_temp[*]-} > 0 )) && eval ${_uninstall} ${_temp[*]}
}

run
