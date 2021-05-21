#!/bin/sh

xcodebuild archive -scheme EarlGrey -archivePath ~/Desktop/EarlGrey-iphone.xcarchive -destination="iOS" -sdk iphoneos SKIP_INSTALL=NO

xcodebuild archive -scheme EarlGrey -archivePath ~/Desktop/EarlGrey-iphonesimulator.xcarchive -destination="iOS Simulator" -sdk iphonesimulator SKIP_INSTALL=NO

xcodebuild -create-xcframework -framework /Users/stefan/Desktop/EarlGrey-iphonesimulator.xcarchive/Products/Library/Frameworks/EarlGrey.framework -framework /Users/stefan/Desktop/EarlGrey-iphone.xcarchive/Products/Library/Frameworks/EarlGrey.framework -output ~/Desktop/EarlGrey.xcframework

rm -rf ~/Desktop/EarlGrey-iphone.xcarchive 
rm -rf ~/Desktop/EarlGrey-iphonesimulator.xcarchive 
