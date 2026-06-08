#!/bin/bash

mypathbinutils=${GENTOO_BINUTILS_REPO:-~/Gentoo/misc/binutils-gdb}
mypathpatches=${GENTOO_BINUTILS_PATCHES_REPO:-~/Gentoo/misc/binutils-patches}

# I plan to extend this script a bit, to also help with the initial
# Gentoo release branch creation. That's why I check so much for both
# git repos... -A

PN="binutils"
PV=${1%/}
pver=$2

if [[ -z ${PV} ]] ; then
	echo "Usage: $0 binutils-version patchset-version-to-be-created"
	echo "Important environment variables: GENTOO_BINUTILS_REPO GENTOO_BINUTILS_PATCHES_REPO"
	echo "Please read the script before trying to use it :)"
	exit 1
fi

# check that we have a gentoo binutils patches git repo

if [[ ! -f "${mypathpatches}/README.Gentoo.patches" ]] || [[ ! -d "${mypathpatches}/.git" ]] ; then
	echo "Error: GENTOO_BINUTILS_PATCHES_REPO needs to point to the main directory of a Gentoo binutils patchset git clone"
	exit 1
fi

# check that we have a gentoo binutils git repo

if [[ ! -d "${mypathbinutils}/bfd" ]] || [[ ! -d "${mypathbinutils}/.git" ]] ; then
	echo "Error: GENTOO_BINUTILS_REPO needs to point to the main directory of a Gentoo binutils-gdb git clone"
	exit 1
fi

# go into the gentoo patches repo

cd "${mypathpatches}"

# check that the working directory is clean

mystatusinfo=$(git status --porcelain)
if [[ ! -z "${mystatusinfo}" ]] ; then
	echo "Error: Your binutils patches working directory is not clean"
	exit 1
fi

mydescpatches=$(git describe)

# go into the gentoo binutils repo

cd "${mypathbinutils}"

# check that we're on a branch gentoo/${PV}
# note that we allow for gentoo-specific patch versions, ie.,
# * the PV 2.37_p1 lives on branch 2.37
# * the PV 2.37.1  lives on branch 2.37.1

mybranchinfo=$(git status --porcelain -b|grep '^##')
mybranch=$(echo ${mybranchinfo}|sed -e 's:^## ::' -e 's:\.\.\..*$::')
if [[ ! "gentoo/binutils-${PV%_p?}" == "${mybranch}" ]] ; then
	echo "Error: Your binutils git repository is on the incorrect branch ${mybranch}; should be gentoo/binutils-${PV%_p?}"
	exit 1
fi

# check that the working directory is clean

mystatusinfo=$(git status --porcelain)
if [[ ! -z "${mystatusinfo}" ]] ; then
	echo "Error: Your binutils working directory is not clean"
	exit 1
fi

mydescbinutils=$(git describe)

# check if the tag already exists

mytaginfo=$(git tag -l|grep "gentoo/binutils-${PV}-${pver}")
if [[ ! -z "${mytaginfo}" ]] ; then
	echo "Error: A tag corresponding to this patch level already exists (gentoo/binutils-${PV}-${pver})"
	exit 1
fi

# luckily binutils git has no /tmp dir and no tar.xz files, but let's better check and be pathologically careful

if [[ -e tmp ]] || [[ -e ${PN}-${PV}-patches-${pver}.tar.xz ]] ; then
	echo "Error: tmp or ${PN}-${PV}-patches-${pver}.tar.xz exists in git"
	exit 1
fi
rm -rf tmp
rm -f ${PN}-${PV}-*.tar.xz

for myname in 0*.patch ; do
	if [[ -e ${myname} ]]; then
		echo "Error: ${myname} exists in git"
		exit 1
	fi
done
rm -f 0*.patch

mkdir -p tmp/patches

# copy README.Gentoo.patches

cp "${mypathpatches}/README.Gentoo.patches" tmp/ || exit 1

echo >> "tmp/README.Gentoo.patches"
echo "Generated with make-tarball.sh ${mydescpatches}" >> "tmp/README.Gentoo.patches"

# create and rename patches

if [[ "${PV}" == "9999" ]]; then
	# working with master is not supported anymore
	echo "Patchsets for git master are not supported anymore"
	exit 1
else
	mytaginfo=$(git tag -l|grep "gentoo/binutils-${PV}-upstream")
	if [[ ! -z "${mytaginfo}" ]] ; then
		startpoint="gentoo/binutils-${PV}-upstream"
	else
		# release branch, start from upstream release tag
		startpoint="binutils-${PV//./_}"
	fi

	echo "Starting from tag ${starttag}"
fi

git format-patch --no-base --no-cover-letter ${startpoint}..HEAD > /dev/null || exit 1

# remove all patches where the summary line starts with:
# - [no-tarball]: not related to upstream tarball
# - [no-patch]: not related to upstream patches
# - "Automatic date update in version.in": daily bumps
# from 2.35 on this should not be needed anymore (no such commits)
rm -f 0???-no-tarball-*.patch
rm -f 0???-no-patch-*.patch
rm -f 0???-Automatic-date-update-in-version.in.patch

# add the extra patch

cp "${mypathpatches}/All/9999-Gentoo-We-make-a-release" tmp/patches/9999-Gentoo-We-make-a-release.patch || exit 1

# move patches into temporary directory

mv 0*.patch tmp/patches/ || exit 1

# add a history file

git log --stat --decorate ${startpoint}..HEAD > tmp/patches/README.history || exit 1

# package everything up

echo "Packaging up ${PN}-${PV}-patches-${pver}.tar.xz"
tar -Jcf ${PN}-${PV}-patches-${pver}.tar.xz \
	-C tmp patches README.Gentoo.patches || exit 1
rm -r tmp

du -b *.tar.xz

# sign the patchset with gpg

echo "Signing ${PN}-${PV}-patches-${pver}.tar.xz with gpg"
gpg -b -o ${PN}-${PV}-patches-${pver}.tar.xz.sig ${PN}-${PV}-patches-${pver}.tar.xz || exit 1

echo "Uploading file to /pub/proj/toolchain/binutils/patches/"
kup putraw ${PN}-${PV}-patches-${pver}.tar.xz ${PN}-${PV}-patches-${pver}.tar.xz.sig /pub/proj/toolchain/binutils/patches/ || exit 1

# tag the commit

echo "Tagging the patchset commit gentoo/binutils-${PV}-${pver}"
git tag -s -m "Gentoo patchset binutils-${PV}-${pver}" "gentoo/binutils-${PV}-${pver}" || exit 1

echo "Pushing the tag"
git push gentoo gentoo/binutils-${PV}-${pver}
