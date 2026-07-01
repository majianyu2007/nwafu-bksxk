// 查询学生基本信息
function queryStudentInformation(xh) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/" + xh + ".do?timestamp=" + timestamp, {},
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}
// 查询已选志愿课程
function queryVolunteered(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/volunteered.do?timestamp=" + timestamp,
        queryParam,
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}
// 查询考试批次
function queryTestBatch() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/batch.do?timestamp=" + timestamp, {},
        "get"
    );
}

// 查询公共信息
function queryPublicInfo(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo.do?timestamp=" + timestamp,
        queryParam,
        "get"
    );
}

// 查询字典
function queryDictionary() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/dictionary.do?timestamp=" + timestamp, {},
        "get"
    );
}
// 查询系统参数
function querySysParam() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doSyncAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/sysparam.do?timestamp=" + timestamp, {},
        "get"
    );
}
// 学生登出
function studentLogOut(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/logout.do?timestamp=" + timestamp,
        queryParam,
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

function autoLogOut() {
	if (loginType == 'cas') {
//		$('#iflogout')[0].src=casUrlOut;
		var iframe = document.createElement('iframe'); 
		iframe.src=casUrlOut;  
		document.body.appendChild(iframe);
	}
    var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/authlogout.do?timestamp=" + timestamp, {}, "get"
    );
}

// 单点登录用户注册
function loginInUserRegister(uid) {
    //var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/register.do?number=" + uid, {},
        "get"
    );
}

function queryVocdeToken() {
    var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/4/vcode.do?timestamp=" + timestamp, {},
        "get"
    );
}

function queryOnlineUsers() {
    var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/onlineUsers.do?timestamp=" + timestamp, {},
        "get"
    );
}

/**
 * 查询选课伦次是否开放(异步)
 */
function queryXklcSfkf(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/batchisopen.do",
        queryParam == null ? {} : queryParam,
        "post",
        {},
        {}
    );
}

/**
 * 查询选课伦次是否开放（同步）
 */
function queryXklcSfkfBySync(queryParam) {
	return BH_UTILS.doSyncAjax(
			BaseUrl + "/sys/xsxkapp/elective/batchisopen.do",
			queryParam == null ? {} : queryParam,
			"post",
			{}
	);
}

//查询学生选课信息
function queryXkxf(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/xkxf.do",
        queryParam,
        "post", 
        {}, 
        {"token": sessionStorage.token}
    );
}

function getDesKeys(){
	return ['this','password','is'];
}