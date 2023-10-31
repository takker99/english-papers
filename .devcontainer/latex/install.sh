#!/bin/bash

# 環境変数を設定
# ConTeXt cache can be created on runtime and does not need to
 # increase image size
export TEXLIVE_INSTALL_NO_CONTEXT_CACHE=1
# As we will not install regular documentation why would we want to
# install perl docs…
export NOPERLDOC=1

apt-get update
# basic utilities for TeX Live installation
apt-get install -qy --no-install-recommends curl git unzip
# miscellaneous dependencies for TeX Live tools
apt-get install -qy --no-install-recommends make fontconfig perl default-jre libgetopt-long-descriptive-perl libdigest-perl-md5-perl libncurses6
# for latexindent (see https://gitlab.com/islandoftex/images/texlive/-/issues/13)
apt-get install -qy --no-install-recommends libunicode-linebreak-perl libfile-homedir-perl libyaml-tiny-perl
# for eps conversion (see https://gitlab.com/islandoftex/images/texlive/-/issues/14)
apt-get install -qy --no-install-recommends ghostscript
# for metafont (see https://gitlab.com/islandoftex/images/texlive/-/issues/24)
apt-get install -qy --no-install-recommends libsm6
# for syntax highlighting
apt-get install -qy --no-install-recommends python3 python3-pygments
# for gnuplot backend of pgfplots (see https://gitlab.com/islandoftex/images/texlive/-/merge_requests/13)
apt-get install -qy --no-install-recommends gnuplot-nox
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/
# bad fix for python handling
ln -s /usr/bin/python3 /usr/bin/python

DOCFILES="${DOCFILES}"
SRCFILES="${SRCFILES}"
SCHEME="${SCHEME}"
# the mirror from which we will download TeX Live
TLMIRRORURL="rsync://rsync.dante.ctan.org/CTAN/systems/texlive/tlnet/"
# whether to create font and ConTeXt caches
GENERATE_CACHES="yes"

cd /tmp

echo "download and install equivs file for dummy package"
curl https://tug.org/texlive/files/debian-equivs-2022-ex.txt --output texlive-local
sed -i "s/2022/9999/" texlive-local
# freeglut3 does not ship with debian testing, so we remove it because there
# is no GUI need in the container anyway (see #28)
sed -i "/Depends: freeglut3/d" texlive-local
apt-get update
# Mark all texlive packages as installed. This enables installing
# latex-related packges in child images.
# Inspired by https://tex.stackexchange.com/a/95373/9075.
apt-get install -qy --no-install-recommends equivs
# at this point also install gpg and gpg-agent to allow tlmgr's
# key subcommand to work correctly (see #21)
apt-get install -qy --no-install-recommends gpg gpg-agent
# we install using rsync so we need to have it installed
apt-get install -qy --no-install-recommends rsync
# we need to change into tl-equis to get it working
equivs-build texlive-local
dpkg -i texlive-local_9999.99999999-1_all.deb
apt-get install -qyf --no-install-recommends
# reverse the cd command from above and cleanup
rm -rf ./*texlive*
# save some space
apt-get remove -y --purge equivs
apt-get autoremove -qy --purge
rm -rf /var/lib/apt/lists/
apt-get clean
rm -rf /var/cache/apt/

echo "Fetching installation from mirror $TLMIRRORURL"
rsync -a --stats "$TLMIRRORURL" texlive
cd texlive

# create installation profile for full scheme installation with
# the selected options
echo "Building with documentation: $DOCFILES"
echo "Building with sources: $SRCFILES"
echo "Building with scheme: $SCHEME"
# choose complete installation


# choose complete installation
echo "selected_scheme scheme-$SCHEME" > install.profile
# … but disable documentation and source files when asked to stay slim
if [ "$DOCFILES" = "no" ]; then
  echo "tlpdbopt_install_docfiles 0" >> install.profile
  echo "BUILD: Disabling documentation files"
fi
if [ "$SRCFILES" = "no" ]; then
  echo "tlpdbopt_install_srcfiles 0" >> install.profile
  echo "BUILD: Disabling source files"
fi
# furthermore we want our symlinks in the system binary folder to avoid
# fiddling around with the PATH
echo "tlpdbopt_autobackup 0" >> install.profile
echo "tlpdbopt_sys_bin /usr/bin" >> install.profile

# actually install TeX Live
./install-tl -profile install.profile
cd ..
rm -rf texlive

# 作業ディレクトリを設定
mkdir /workdir
cd /workdir

echo "Set PATH to $PATH"
$(find /usr/local/texlive -name tlmgr) path add

# Temporary fix for ConTeXt (#30)
sed -i '/package.loaded\["data-ini"\]/a if os.selfpath then environment.ownbin=lfs.symlinktarget(os.selfpath..io.fileseparator..os.selfname);environment.ownpath=environment.ownbin:match("^.*"..io.fileseparator) else environment.ownpath=kpse.new("luatex"):var_value("SELFAUTOLOC");environment.ownbin=environment.ownpath..io.fileseparator..(arg[-2] or arg[-1] or arg[0] or "luatex"):match("[^"..io.fileseparator.."]*$") end' /usr/bin/mtxrun.lua

# pregenerate caches as per #3; overhead is < 5 MB which does not really
# matter for images in the sizes of GBs; some TL schemes might not have
# all the tools, therefore failure is allowed
if [ "$GENERATE_CACHES" = "yes" ]; then
  echo "Generating caches and ConTeXt files"
  (luaotfload-tool -u || true)
  # also generate fontconfig cache as per #18 which is approx. 20 MB but
  # benefits XeLaTeX user to load fonts from the TL tree by font name
  cp "$(find /usr/local/texlive -name texlive-fontconfig.conf)" /etc/fonts/conf.d/09-texlive-fonts.conf
  fc-cache -fsv
  if [ -f "/usr/bin/context" ]; then
    mtxrun --generate
    texlua /usr/bin/mtxrun.lua --luatex --generate
    context --make
    context --luatex --make
  fi
else
  echo "Not generating caches or ConTeXt files"
fi

# test the installation; we only test the full installation because
# in that, all tools are present and have to work
if [ "$SCHEME" = "full" ]; then
  latex --version
  printf '\n'
  biber --version
  printf '\n'
  xindy --version
  printf '\n'
  arara --version
  printf '\n'
  context --version
  printf '\n'
  context --luatex --version
  printf '\n'
  if [ "$DOCFILES" = "yes" ]; then texdoc -l geometry; fi
  if [ "$SRCFILES" = "yes" ]; then kpsewhich amsmath.dtx; fi
fi

python --version
printf '\n'
pygmentize -V
printf '\n'
