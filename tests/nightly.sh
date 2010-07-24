#!/bin/bash

# set -x

# USAGE NOTES:
# Run nightly.sh -h for quick help
# When something goes wrong, find and check tests.log
# Code is checked out into TOPDIR
# Swift is installed in its source tree
# The run is executed in RUNDIR (TOPDIR/RUNDIRBASE)
# The build test is started in TOPDIR
# Everything for a Swift test is written in its RUNDIR
# The temporary output always goes to OUTPUT (TOPDIR/exec.out)

printhelp() {
  echo "nightly.sh <options> <output>"
  echo ""
  echo "usage:"
  printf "\t -c      Do not clean                    \n"
  printf "\t -g      Do not run grid tests           \n"
  printf "\t -h      This message                    \n"
  printf "\t -p      Do not build the package        \n"
  printf "\t -s      Do not do a fresh svn checkout  \n"
  printf "\t -x      Do not continue after a failure \n"
  printf "\t output  Location for output (TOPDIR)    \n"
}

# Defaults:
CLEAN=1
BUILD_PACKAGE=1
GRID_TESTS=1
SKIP_CHECKOUT=0
ALWAYS_EXITONFAILURE=0
# The directory in which to start:
TOPDIR=$PWD

while [ $# -gt 0 ]; do
  case $1 in
    -c)
      CLEAN=0
      shift;;
    -g)
      GRID_TESTS=0
      shift;;
    -h)
      printhelp
      exit 0;;
    -p)
      BUILD_PACKAGE=0
      shift;;
    -s)
      SKIP_CHECKOUT=1
      shift;;
    -x)
      ALWAYS_EXITONFAILURE=1
      shift;;
    *)
      TOPDIR=$1
      shift;;
  esac
done

LOGCOUNT=0
SEQ=1
DATE=$( date +"%Y-%m-%d" )
TIME=$( date +"%T" )

RUNDIRBASE="run-$DATE"
RUNDIR=$TOPDIR/$RUNDIRBASE
LOGBASE=$RUNDIRBASE/tests.log
LOG=$TOPDIR/$LOGBASE
OUTPUT=$TOPDIR/exec.out

HTMLPATH=$RUNDIRBASE/tests-$DATE.html
HTML=$TOPDIR/$HTMLPATH

BRANCH="branches/tests-01"

SCRIPTDIR=$( dirname $0 )

cd $TOPDIR
mkdir -p $RUNDIR
[ $? != 0 ] && echo "Could not mkdir: $RUNDIR" && exit 1

header() {
        CURRENT=$SCRIPTDIR/html/current.html
	sed "s@_HTMLBASE_@$HTMLPATH@" < $CURRENT > $TOPDIR/current.html

        HEADER=$SCRIPTDIR/html/header.html
        HOST=$( hostname )
        SEDCMD="s/_DATE_/$DATE/;s/_TIME_/$TIME/;s/_HOST_/$HOST"/
	sed $SEDCMD < $HEADER > $HTML
	FIRSTTEST=1
}

html() {
	echo $@ >>$HTML
}

a_name() {
  NAME=$1
  html "<a name=\"$NAME\">"
}

a_href() {
  HREF=$1
  TEXT=$2
  html "<a href=\"$HREF\">$TEXT</a>"
}

footer() {
	MONTHS=("" "Jan" "Feb" "Mar" "Apr" "May" "Jun" \
                   "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
	html "</tr></table></tr></table>"

	if [ "$BINPACKAGE" != "" ]; then
		FBP=$RUNDIR/$BINPACKAGE
		SIZE=`ls -hs $FBP`
		SIZE=${SIZE/$FBP}
		cat <<DOH >>$HTML
	<h1>Binary packages</h1>
	<a name="#packages">
	<a href="$BINPACKAGE">$BINPACKAGE</a> ($SIZE)<br>
DOH
	fi

	LASTYR="00"
	LASTMO="00"
	html "<h1>Older tests</h1>"
	html '<a name="older">'
	html "<table><tr>"
	for OLDER in `ls $OUTDIR/tests-*.html|sort`; do
		O=`basename $OLDER`
		YR=${O:6:2}
		MO=${O:8:2}
		DY=${O:10:2}
		if echo "$DY$MO$YR"|egrep -v "[0-9]{6}"; then
			YR=${O#tests-}
			YR=${YR%.html}
			MO=0
			DY=$YR
		else
			YR="20$YR"
		fi
		if [ $LASTYR != $YR ]; then
			html "</tr></table>"
			html "<h2>$YR</h2>"
			LASTYR=$YR
		fi
		if [ $LASTMO != $MO ]; then
			html "</tr></table>"
			html "<h3>${MONTHS[$MO]}</h3>"
			html "<table border=\"0\"><tr>"
			LASTMO=$MO
		fi
		SUCCESS=`grep 'class="success"' $OLDER|wc -l`
		FAILURE=`grep 'class="failure"' $OLDER|wc -l`
		if [ "$SUCCESS$FAILURE" == "00" ]; then
			COLOR="#e0e0e0"
		else
			COLOR=`perl -e "printf \"#%02x%02x%02x\", $FAILURE/($SUCCESS+$FAILURE)*220+35, $SUCCESS/($SUCCESS+$FAILURE)*220+35, 40;"`
		fi
		html "<td bgcolor=\"$COLOR\"><a href=\"$O\">$DY</a></td>"
	done
	html "</tr></table><br><br>"
	cat <<DOH >>$HTML
	<a href="addtests.html">How to add new tests</a>
	</body>
</html>
DOH
}

outecho() {
	TYPE=$1
	shift
	echo "<$TYPE>$1|$2|$3|$4|$5|$6|$7|$8|$9|"
}

out() {
        # echo $@
	TYPE=$1
	if [ "$TYPE" == "test" ]; then

		NAME=$2
		SEQ=$3
		CMD=$4
		RES=$5

		if [ "$FIRSTTEST" == "1" ]; then
			html "<h1>Test results</h1>"
                        a_name "tests"
			a_href "tests.log" "Output log from tests"
			html "<table border=\"0\">"
			FIRSTTEST=0
		else
			if [ "$FLUSH" == "1" ]; then
				html "</tr></table></tr>"
			fi
		fi

		if [ "$TESTPART" != "" ]; then
			html "<tr class=\"part\"><th colspan=\"2\">$TESTPART</th></tr>"
			TESTPART=
		fi

		if [ "$FLUSH" == "1" ]; then
			html "<tr class=\"testline\"><th align=\"right\">$NAME: </th><td><table border=\"0\"><tr>"
		fi
		if [ ${#SEQ} -gt 2 ]; then
			WIDTH=""
		else
			WIDTH="width=\"20\""
		fi
		if [ "$RES" == "Passed" ]; then
			html "<td class=\"success\" $WIDTH title=\"$CMD\">"
			html "<a href=\"$TLOG\">$SEQ</a>"
		else
                        echo "FAILED"
                        cat $TLOG < /dev/null
			html "<td class=\"failure\" $WIDTH title=\"$CMD\">"
			html "<a href=\"$TLOG\">$SEQ</a>"
		fi
		html "</td>"

	elif [ "$TYPE" == "package" ]; then
		BINPACKAGE=$2
	else
		html $@
	fi
}

aexec() {
        declare -p PWD
	echo "Executing: $@" >>$LOG
	rm -fv $OUTPUT
	LASTCMD="$@"
	"$@" > $OUTPUT 2>&1
        head $OUTPUT
	EXITCODE=$?
	if [ "$EXITCODE" == "127" ]; then
		echo "Command not found: $@" > $OUTPUT
	fi
	if [ -f $OUTPUT ]; then
		cat $OUTPUT >>$LOG
	fi
}

# TLOG = this (current) log
tlog() {
	TLOG="output_$LOGCOUNT.txt"
	rm -fv $TLOG
	banner "$LASTCMD" $RUNDIR/$TLOG
	if [ -f $OUTPUT ]; then
		cp -v $OUTPUT $RUNDIR/$TLOG 2>>$LOG
	fi
	let "LOGCOUNT=$LOGCOUNT+1"
}

# Fake exec
fexec() {
	FLUSH=1
	banner "$TEST (faked)"
	echo "Faking $TEST"
	EXITCODE=0
	LASTCMD=""
	vtest
}

stars() {
  for i in {1..90}
  do
    printf "*"
  done
  echo
}

banner() {
	if [ "$2" == "" ]; then
		BOUT=$LOG
	else
		BOUT=$2
	fi
        {
	  echo ""
          # stars
	  echo "* $1"
	  # stars
        } >>$BOUT
}

# Execute as part of test set
pexec() {
	banner "$TEST (part $SEQ)"
	echo "Executing $TEST (part $SEQ)"
	aexec "$@"
	ptest
	let "SEQ=$SEQ+1"
	FLUSH=0
}

ssexec() {
	SEQSAVE=$SEQ
	SEQ=$1
	shift
	banner "$TEST (part $SEQ)"
	echo "Executing $TEST (part $SEQ)"
	aexec "$@"
	ptest
	SEQ=$SEQSAVE
	FLUSH=0
}

# Execute final test in set
vexec() {
	if [ "$SEQ" == "1" ]; then
		banner "$TEST"
		echo "Executing $TEST"
	else
		banner "$TEST (part $SEQ)"
		echo "Executing $TEST (part $SEQ)"
	fi
	aexec "$@"
	vtest
	SEQ=1
	FLUSH=1
}

ptest() {
	if [ "$EXITCODE" == "0" ]; then
		RES="Passed"
	else
		RES="Failed"
	fi
	tlog
	out test "$TESTLINK" $SEQ "$LASTCMD" $RES $TLOG
	if [ "$EXITONFAILURE" == "true" ]; then
		if [ "$EXITCODE" != "0" ]; then
			exit $EXITCODE
		fi
	fi
}

vtest() {
	EC=$?
	if [ "$EXITCODE" == "0" ]; then
		RES="Passed"
	else
		RES="Failed"
	fi
	tlog
	out test "$TESTLINK" $SEQ "$LASTCMD" $RES $TLOG
	if [ "$EXITCODE" != "0" ]; then
		if [ "$EXITONFAILURE" == "true" ]; then
			exit $EXITCODE
		fi
	fi
}

build_package() {
  TEST="Package"
  pexec cd $SWIFT_HOME/lib
  pexec rm -f castor*.jar *gt2ft*.jar ant.jar
  pexec cd $TOPDIR
  vexec tar -pczf $RUNDIR/swift-$DATE.tar.gz $SWIFT_HOME
  out package "swift-$DATE.tar.gz"
}

date > $LOG
FLUSH=1

header
cd $TOPDIR

TESTPART="Part I: Build"
EXITONFAILURE=true
if [ "$SKIP_CHECKOUT" != "1" ]; then
	TEST="Checkout CoG"
	pexec rm -rf cog
        COG="https://cogkit.svn.sourceforge.net/svnroot/cogkit/trunk/current/src/cog"
	vexec svn co $COG

	TEST="Checkout Swift"
        pexec cd cog/modules
	pexec rm -rf swift
	vexec svn co https://svn.ci.uchicago.edu/svn/vdl2/$BRANCH swift
fi

TEST="Compile"
pexec cd $TOPDIR/cog/modules/swift
if [ $CLEAN == "1" ]; then
  pexec rm -rf dist
fi
vexec ant -quiet dist
SWIFT_HOME=$TOPDIR/cog/modules/swift/dist/swift-svn

if [ $BUILD_PACKAGE = "1" ]; then
  build_package
fi

PATH=$SWIFT_HOME/bin:$PATH
cd $TOPDIR
which swift
TESTDIR=$TOPDIR/cog/modules/swift/tests
cd $RUNDIR

if [ $ALWAYS_EXITONFAILURE != "1" ]; then
    EXITONFAILURE=false
fi
TESTPART="Part II: Local Tests"

for TEST in $( ls $TESTDIR/*.swift ); do # $TESTDIR/*.dtm
  TESTNAME=$( basename $TEST)
  echo TESTNAME: $TESTNAME $TESTDIR/$TESTNAME
  cp -uv $TESTDIR/$TESTNAME .
  sed "s@_WORK_@$PWD/work@" < $TESTDIR/sites/localhost.xml > sites.xml

  TESTLINK="<a href=\"$TESTNAME\">$TESTNAME</a>"

  for ((i=0; $i<9; i=$i+1)); do
    pexec swift -sites.file sites.xml $TESTNAME
  done
  vexec swift -sites.file sites.xml $TESTNAME
done

if [ $GRID_TESTS == "0" ]; then
  exit
fi

TESTPART="Part III: Grid Tests"

for TEST in `ls $TESTDIR/*.dtm $TESTDIR/*.swift`; do
	BN=`basename $TEST`
	echo $BN
	cp $TESTDIR/$BN .

	TESTNAME=${BN%.dtm}
	TESTNAME=${TESTNAME%.swift}
	TEST="<a href=\"$RUNDIRBASE/$BN\">$TESTNAME</a>"

	ssexec "Compile" vdlc $BN
	for ((i=0; $i<9; i=$i+1)); do
		pexec swift -sites.file ~/.vdl2/sites-grid.xml $TESTNAME.kml
	done
	vexec swift -sites.file ~/.vdl2/sites-grid.xml $TESTNAME.kml
done

#Don't remove me:
footer