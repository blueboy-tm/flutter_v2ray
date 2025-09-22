//
//  LibXrayWrapper.h
//  flutter_v2ray
//
//  C wrapper for LibXray functions
//

#ifndef LibXrayWrapper_h
#define LibXrayWrapper_h

#include <stdio.h>

// Import LibXray C functions
char* CGoXrayVersion(void);
char* CGoRunXray(char* base64Text);
char* CGoStopXray(void);
char* CGoTestXray(char* base64Text);
char* CGoQueryStats(char* base64Text);

#endif /* LibXrayWrapper_h */
