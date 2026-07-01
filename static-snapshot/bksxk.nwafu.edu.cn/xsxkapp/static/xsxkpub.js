/**
 * 2018-10-24:wzp存放公共方法
 */

function changeCopyRight(){
	var cp = sessionStorage.getItem('copyright');
	if(cp && cp!=='null' && cp.length>0){
		var $copyright = $('#cv-copyright');
		if($copyright){
			$copyright.html(cp);
		}
    }
}
/**
 * 查询名人名言
 */
function queryCelebrityFamous() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/celebrityfamous.do?timestamp=" + timestamp, {},
        "get"
    );
}

;(function(_mode) {

    _mode.init = function() {
        setCelebrityFamous();
        xsxkpub.changeCopyRight();
    };

    function setCelebrityFamous() {
        var dataList = JSON.parse(sessionStorage.getItem('celebrityFamous'));
        if (dataList != null && dataList.length > 0) {
            initFooterMessage(dataList[randomNumBoth(0, dataList.length - 1)]);
        } else {
            queryCelebrityFamous().done(function(resp) {
                var code = resp.code;
                if (code != null && code == '1') {
                    var dataList = resp.dataList;
                    if (dataList != null && dataList.length > 0) {
                        var randomIndex = randomNumBoth(0, dataList.length - 1);
                        initFooterMessage(dataList[randomIndex]);
                    }
                }
            });
        }
    };

    /**
     * 设置页面数据
     */
    function initFooterMessage(_data) {
        $("#ecDiv").html(_data.englishContent);
        $("#cDiv").html(_data.content);
        $("#authorDiv").html(_data.author);
    };

    /**
     * 数字区间取随机数
     */
    function randomNumBoth(Min, Max) {
        var Range = Max - Min;
        var Rand = Math.random();
        //四舍五入
        var num = Min + Math.round(Rand * Range);
        return num;
    };
})(window.CVFotterMessage = window.CVFotterMessage || {});

/**
 * 抽去grablessonsBS.js,curriculavariableBs.js中的公用方法
 */
/**
 * 查询推荐课程
 */
function queryRecommendedCourse(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/recommendedCourse.do",
        queryParam == null ? {} : queryParam,
        "post",
        {},
        {"token" : sessionStorage.token}
    );
}
/**
 * 查询课程（侧边栏课程搜索用）
 */
function queryCourse(queryParam) {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/course.do?timestamp=" + timestamp,
        queryParam == null ? {} : queryParam,
        "get",
        {},
        {"token" : sessionStorage.token}
    );
}
/**
 * 查询校公选课
 */
function queryPublicCourse(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/publicCourse.do",
        queryParam == null ? {} : queryParam,
        "post",
        {},
        {"token" : sessionStorage.token}
    );
}

/**
 * 查询方案内选课
 */
function queryProgramCourse(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/programCourse.do",
        queryParam == null ? {} : queryParam,
        "post",
        {},
        {"token" : sessionStorage.token}
    );
}

/**
 * 查询志愿等级
 */
function queryVolunteerData() {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/volunteer.do?timestamp=" + timestamp,
        {},
        "get",
        {async: false},
        {"token" : sessionStorage.token}
    );
}

/**
 * 添加志愿选课
 */
function addVolunteer(addParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/volunteer.do",
        addParam,
        "post",
        {},
        {"token" : sessionStorage.token}
    );
}

function queryCourseCanSelectVolunteer(queryParam) {
	var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/course/volunteer.do?timestamp=" + timestamp,
        queryParam,
        "get",
        {},
        {"token" : sessionStorage.token}
    );
}

function queryUnSuccessful(xh, isRead, xklcdm) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/unsuccessful.do?isRead=" + isRead + "&studentCode=" + xh + "&electiveBatchCode=" + xklcdm,
        {},
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

function submitUnSuccessful(xh, wids) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/submit/unsuccessful.do?wids=" + wids + "&studentCode=" + xh,
        {},
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

/**
 * 查询教学班信息
 */
function queryJxbInfo(xklcdm, jxbid) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/publicinfo/queryjxb.do?xklcdm=" + xklcdm + "&jxbid=" + jxbid,
        {},
        "get", {}, {
            "token": sessionStorage.token
        }
    );
}

/**
 * 查询实验课程
 */
function queryTestCourse(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/testCourse.do",
        queryParam == null ? {} : queryParam,
        "post",
        {},
        {"token" : sessionStorage.token}
    );
}

function queryCourseData(queryParam) {
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/elective/queryCourse.do",
        queryParam == null ? {} : queryParam,
        "post", {}, {
            "token": sessionStorage.token
        }
    );
}

function queryYxNjZyData(type) {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/publicinfo/fx/" + type + '.do' + "?timestamp=" + timestamp,
			{},
			"get", {}, {
				"token": sessionStorage.token
			}
	);
}

function querySkYxNjZyData(type) {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/publicinfo/zx/" + type + '.do' + "?timestamp=" + timestamp,
			{},
			"get", {}, {
				"token": sessionStorage.token
			}
	);
}

function querySfCanChoose(xh,jxbid,xklcdm) {
	var timestamp = new Date().getTime();
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/util/canchoose.do" + "?xh=" + xh + "&jxbid=" + jxbid + "&xklcdm=" + xklcdm + "&timestamp=" + timestamp,
			{},
			"get", {}, {
				"token": sessionStorage.token
			}
	);
}

//查询所属方案
function queryFaDetail(param) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/elective/course/kcssfa.do",
			param==null?{}:param,
			"post", {}, {
				"token": sessionStorage.token
			}
	);
}
//选课轮次确认须知
function makeSureLcxz(param) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/student/xklcqr.do",
			param==null?{}:param,
			"post", {}, {
				"token": sessionStorage.token
			}
	);
}


//export
var xsxkpub = {
	changeCopyRight : changeCopyRight,
	CVFotterMessage : CVFotterMessage
};

/*兼容南师需求*/
//更改通识课名称
function changeTskName(value){
	$('.tskxm').html(value);
}
//隐藏校公选课中的教学班详情
function hidePublicJxbxq(){
	$('.public-jxbxq').hide();
}
//隐藏校公选课中的分页按钮
function hidePublicFoot(){
	$('#publicUp').closest('.cv-foot').hide();
}
//绑定校公选课滚动翻页功能
function bindPublicScrollPage() {
	window.isScrolling = false;
	$(window).off('scroll').on('scroll', function(){
		if(!window.isScrolling){
			window.isScrolling = true;
			setTimeout(function(index, obj){
				if(sessionStorage.teachingClassType == 'XGXK'){
					if ($(document).height() - $(window).scrollTop() - $(window).height() < 220) {
						if(publicPageNumber < (publicTotalPage - 1)){
							publicPageNumber = publicPageNumber + 1;
				            CVPublicCourse.listReload(undefined, undefined, true);
						}
					}
				}
				window.isScrolling = false;
			}, 500);
		}
    });
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

//查询队列信息
function queryStudentQueue(queryParam) {
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/elective/queryStudentQueue.do",
			queryParam,
			"get", 
			{}, 
			{"token": sessionStorage.token}
	);
}

//单点登录用户注册
function loginInUserRegister(uid) {
    //var timestamp = new Date().getTime();
    return BH_UTILS.doAjax(
        BaseUrl + "/sys/xsxkapp/student/register.do?number=" + uid, {},
        "get"
    );
}

//时间地点换行处理
function dealTeachingPlace(teachingPlace){
	if(!teachingPlace){
		return '';
	}
	teachingPlace = teachingPlace.replace(/周,/g, '###');
	teachingPlace = teachingPlace.replace(/\),/g, '***');
	teachingPlace = teachingPlace.replace(/,/g, ' <br /> ');
	teachingPlace = teachingPlace.replace(/###/g, '周,');
	teachingPlace = teachingPlace.replace(/\*\*\*/g, '),');
	return teachingPlace;
}

function getUuid(){
	var s = [];
    var hexDigits = "0123456789abcdef";
    for (var i = 0; i < 36; i++) {
        s[i] = hexDigits.substr(Math.floor(Math.random() * 0x10), 1);
    }
    s[14] = "4";
    s[19] = hexDigits.substr((s[19] & 0x3) | 0x8, 1);
    s[8] = s[13] = s[18] = s[23] = "";
    return s.join("");
}

function dealEmptyData(data) {
    if (!data) {
        return false;
    }
    for (var key in data) {
        if (String(data[key]) == 'null' || String(data[key]) == 'undefined') {
            data[key] = '';
        }
    }
    return data;
}

function initProcessInterval(callback){
	if($('.studentStateTip').lenght > 0){
		$('.studentStateTip').remove();
	}
	var html = '<div class="studentStateTip" style="position: fixed;top: 56px;left: 47%;z-index: 100000;padding: 10px 20px;">' +
		'<span style="color: #EF971C;padding-left: 10px;">学生提交的操作正在处理中。。。</span>' +
		'<img class="studentStateClose" style="vertical-align: top;padding: 0 5px;cursor: pointer;" src="' + 
				resUrl + '/public/images/common/icon-close.png">' +
	'</div>';
	$('body').append(html);
	$('body').off('click', '.studentStateClose').on('click', '.studentStateClose', function(e){
		clearProcessInterval(callback);
	});
	window.intervalTime = 0;
	var getProcessRequest = function(){
		window.intervalTime++;
		if(window.intervalTime > 10){
			clearTimeout(window.processInterval);
			$('.studentStateTip>span').html('请求超时，请稍后再试！').css({
				color: '#E24034'
			});
		}else{
			queryOperateProcess().done(function(resp){
				if(resp.code == '1' || resp.code == '-1'){
					clearProcessInterval(callback, resp);
				}else{
					setTimeout(function(){
						getProcessRequest();
					}, 1000);
				}
			});
		}
	};
	getProcessRequest();
}

function clearProcessInterval(callback, resp){
	$('.studentStateTip').remove();
	if(window.processInterval){
		clearTimeout(window.processInterval);
	}
	if(callback){
		callback(resp);
	}
}

function queryOperateProcess() {
	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
	return BH_UTILS.doAjax(
			BaseUrl + "/sys/xsxkapp/elective/studentstatus.do",
			{studentCode: studentInfo.code},
			"post", 
			{}, 
			{"token": sessionStorage.token}
	);
}

function checkIsConflict($this){
	var currentBatch = JSON.parse(sessionStorage.getItem('currentBatch'));
	var isConflict = $this.attr('isConflict');
	if(isConflict != '1'){
		return true;
	}
	var retakeTypeDetail = $this.attr('retakeTypeDetail');
	var retakeType = $this.attr('retakeType');
	if(retakeTypeDetail == '3' || retakeType == '02' || retakeType == '03'){
		if((retakeTypeDetail == '3' && currentBatch.refreshNoCheckTimeConflict == '1') || 
		   ((retakeType == '02' || retakeType == '03') && currentBatch.retakeNoCheckTimeConflict == '1')){
			return true;
		}else{
			return false;
		}
	}
	if(currentBatch.noCheckTimeConflict == '1'){
		return true;
	}
	return false;
}
