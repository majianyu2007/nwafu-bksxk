// 志愿等级数据（数组）
var volunteerData;
// 列表每页的数量
var pageSize = 10;

// 课程数据列表
var courseDataList = null;

// 推荐选课页码
var recommendPageNumber = 0;
// 推荐选课总页数
var recommendTotalPage = 0;
// 推荐选课排序方式
var recommendOrder = null;

// 方案内选课页码
var programPageNumber = 0;
// 方案内选课总页数
var programTotalPage = 0;
// 方案内选课排序方式
var programOrder = null;

// 方案外选课页码
var unProgramPageNumber = 0;
// 方案外选课总页数
var unProgramTotalPage = 0;
// 方案外选课排序方式
var unProgramOrder = null;

//方案外选课-所属方案页码
var unProgramFalistPageNumber = 0;
// 方案外选课-所属方案总页数
var unProgramFalistTotalPage = 0;

// 校公选课页码
var publicPageNumber = 0;
    // 校公选课总页数
var publicTotalPage = 0;
// 校公选课排序方式
var publicOrder = null;

// 重修选课页码
var retakePageNumber = 0;
// 重修选课总页数
var retakeTotalPage = 0;
// 重修选课排序方式
var retakeOrder = null;

// 体育选课页码
var sportPageNumber = 0;
// 体育选课总页数
var sportTotalPage = 0;
// 体育选课排序方式
var sportOrder = null;

// 辅修选课页码
var minorPageNumber = 0;
// 辅修选课总页数
var minorTotalPage = 0;
// 辅修选课排序方式
var minorOrder = null;

var schoolTotalPage = 0;
var schoolPageNumber = 0;
var schoolOrder = null;

var selectIndex = null;

var noDataHtml = '<div style="height:250px;margin-top:125px"><h4>没有数据</h4></div>';

var selectCourseIsOpen = false;

/**
 * 全局变量
 */
;
(function(_params) {
    /**
     * 重修选课类型
     */
	_params.cxxklx = {
        1: '缓考首修',
        2: '重修'
    };
	var sykbs = JSON.parse(sessionStorage.getItem('sysParam'))['displayNameTest'];
	_params.sykbs = sykbs ? sykbs : '实验课';
})(window.CVParams = window.CVParams || {});

/**
 * 侧边栏
 */
;
(function(_aside) {
    /**
     * 事件监听
     */
    _aside.eventsListen = function() {
        eventsListen();
    };

    /**
     * 打开侧边栏
     */
    _aside.open = function() {
        openAside();
    };

    /**
     * 关闭侧边栏
     */
    _aside.close = function() {
        closeAside();
    };

    /**
     * 事件监听
     */
    function eventsListen() {
        var $aside = $('#cvAside');   

        //点击mini条的项,切换内容
        $aside.on('click', '.cvMiniIconFlag', function(e) {
            contentChange($(this), e);
        });

        //点击非侧边栏的地方关闭侧边栏
        $('body').on('click', function(e) {
            var $target = $(e.target || e.srcElement);
            if ($target.closest('.cv-aside').length === 0 && $target.closest('.cv-dropdown-dialog').length === 0) {
                closeAside();
            }
        });
    }

    /**
     * 打开侧边栏
     */
    function openAside() {
    	CVDialog.unScroll();
        $('#cvAside').addClass('cv-expand');
    }

    /**
     * 关闭侧边栏
     */
    function closeAside() {
    	CVDialog.restoreScroll();
        $('#cvAside').removeClass('cv-expand');
    }

    /**
     * 内容显示切换
     * @param $item
     */
    function contentChange($item, event) {
        var contentIds = {
            user: '#cvAsideUser',
            course: '#cvAsideCourse',
            search: '#cvAsideSearch',
            choice: '#cvAsideChoice',
            unsuccessful: '#cvUnsuccessfulCourse'
        };
        var $mini = $item.parent();
        var $aside = $('#cvAside');
        var $content = $aside.children('.cv-content');
        var type = $item.attr('type');

        $mini.children('div').removeClass('cv-active');
        $item.addClass('cv-active');

        $content.children('div').removeClass('cv-active');
        $(contentIds[type]).addClass('cv-active');

        initAsideDate(type, event);
    }
})(window.CVAside = window.CVAside || {});

/**
 * 专家模式的课程卡片
 */
;
(function(_card) {
    /**
     * 获取卡片html
     * @param _data {object}
     * @param _data.title {string}
     * @param _data.time {string}
     * @param _data.selected {boolean}
     * @returns {*}
     */
    _card.getHtml = function(_data) {
        return getHtml(_data);
    };

    function getHtml(_data) {
        var template =
            '<div id="@courseDiv" class="cv-course-card" canOperate="@canOperate" retakeTypeDetail="@retakeTypeDetail" retakeType="@retakeType" canSelect="@canSelect" isFull="@isFull" isConflict="@isConflict" isChoose="@isChoose" limitGender="@limitGender" capacityOfMale="@capacityOfMale" capacityOfFemale="@capacityOfFemale" numberOfMale="@numberOfMale" numberOfFemale="@numberOfFemale">' +
            '<div class="cv-info">' +
            '<h5>' +
            '<span class="cv-info-title" title="@subTeacher">@teacher</span>' +
            '<button class="cv-btn cv-select-flag cv-tag @volunteerClass" type="button">@volunteerText</button>' +
            '</h5>' +
            '<div class="tsTag">' +
            '<button class="cv-btn cv-tag cv-danger @isConflictClass" type="button" title="@confilctDesc">@isConflictMsg</button>' +
            '<button class="cv-btn cv-tag cv-danger cv-isfull @isFullClass" type="button">@isFullMsg</button>' +
            '<button class="cv-btn cv-tag cv-success @hasTestMsgClass" type="button">@hasTestMsg</button>' +
            '</div>' +
            '<div title="@teachingPlace">@time</div>' +
            '<div class="cv-caption-text" id="@remainingCapacityId">@remainingCapacity</div>' +
            '@bookDetail' +
            '<div class="cv-caption-text cv-operation">'+
            '<div style="text-align:left;margin-right:0%"><font color="red">@conflictHour</font></div>'+
            '<button class=" cv-operation cv-btn cv-btn-cancel cv-jxbDetail" type="button" data-hasCourseUrl="@hasCourseUrl" data-courseUrl="@courseUrl" tcId="@detailId" style="margin-left:0px">教学班详情</button>' + 
            	'<button class="cv-btn cv-tag cv-delete-volunteer @deleteVolunteerClass" type="button" capacitySuffix="@capacitySuffix" tcId="@delTcId">退选</button>' + 
            	'<span class="queue-state @notInQueue">队列处理中</span></div>' +
            '</div>' +

            '<div class="cv-operate">' +
            '<div>@bookContent</div>' +
            '<div style="padding-top: 10px;">' +
            '<button class="cv-btn cv-btn-chose" hasBook="@hasBook" campus="@campus" teachCampus="@teachCampus" tcId="@tcId" capacitySuffix="@capacitySuffix" hasTest="@hasTest">@btnMsg</button>' +
            '<button class="cv-btn cv-btn-cancel">取消</button>' +
            '</div>' +
            '</div>' +
            '</div>';

        var teacher = _data.teacherName;
        var courseIndex = _data.courseIndex;
        var teachingPlace = _data.teachingPlace;
        var capacity = _data.classCapacity;
        var tcId = _data.teachingClassID;
        var courseNumber = _data.courseNumber;
        var firstVolunteer = _data.numberOfFirstVolunteer;
        var classCapacity = _data.classCapacity;
        var remainingCapacity = '';
        var isFull = _data.isFull;
        var isConflict = _data.isConflict;
        var limitGender = _data.limitGender;
        if (limitGender == null) {
            limitGender = '0';
        }
        
        var courseUrl = _data.courseUrl?_data.courseUrl:'';
        var hasCourseUrl = 0;
        if(courseUrl){
        	hasCourseUrl = 1;
        }
        
        var capacityOfMale = _data.capacityOfMale;
        var capacityOfFemale = _data.capacityOfFemale;
        var numberOfMale = _data.numberOfMale;
        var numberOfFemale = _data.numberOfFemale;
        var capacitySuffix = _data.capacitySuffix;
        var inQuene = _data.inQuene;
        
        var canSelect = '';
        if (parseInt(firstVolunteer) < parseInt(classCapacity)) {
            remainingCapacity += firstVolunteer + '/' + classCapacity + ' 可选';
            canSelect = '1';
        } else {
            remainingCapacity += classCapacity + ' 不可选';
            canSelect = '0';
        }
        
        if(limitGender == 1){
        	if(parseInt(capacityOfMale) > 0){
        		remainingCapacity += '<span style="display: inline-block;margin-left: 5px;">';
        		if(parseInt(numberOfMale) < parseInt(capacityOfMale)){
        			remainingCapacity += numberOfMale + '/' + capacityOfMale + '(男)';
        		}else{
        			remainingCapacity += '男生已满';
        		}
        		remainingCapacity += '</span>';
        	}
        	if(parseInt(capacityOfFemale) > 0){
        		remainingCapacity += '<span style="display: inline-block;margin-left: 5px;">';
        		if(parseInt(numberOfFemale) < parseInt(capacityOfFemale)){
        			remainingCapacity += numberOfFemale + '/' + capacityOfFemale + '(女)';
        		}else{
        			remainingCapacity += '女生已满';
        		}
        		remainingCapacity += '</span>';
        	}
        }
        
        var volunteerText = '';
        var volunteerClass = 'cv-block-hide';
        var isChoose = _data.isChoose;
        if (isChoose != null && isChoose == '1') {
            volunteerClass = 'cv-one';
            volunteerText = '已选';
        } else {
            volunteerClass = 'cv-block-hide';
        }

        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
        var electiveTacticCode = electiveBatch.tacticCode;
        var deleteVolunteerClass  = '';
        if (electiveTacticCode != null && electiveTacticCode == '02') {
            deleteVolunteerClass = 'cv-block-hide';
        } else if (isChoose == '1') {
            deleteVolunteerClass = '';
        } else if (isChoose == '0' || isChoose == null) {
            deleteVolunteerClass = 'cv-block-hide';
        }

        teacher = teacher == null ? "教师未安排" : teacher;
        var subTeacher = teacher;
        // 教学班类型
        var teachingClassType = sessionStorage.getItem("teachingClassType");
        var sportName = _data.sportName;
        var engpName = _data.engpName;
        if (teachingClassType == 'TYKC' && sportName != null) {
           teacher = '[' + courseIndex + '-' + sportName + ']' + teacher;
        }else if(engpName){
        	teacher = '[' + courseIndex + '-' + engpName + ']' + teacher;
            subTeacher = '[' + courseIndex + '-' + engpName + ']' + subTeacher;
        }else {
            teacher = '[' + courseIndex + ']' + teacher;
            subTeacher = '[' + courseIndex + ']' + subTeacher;
        }
        
        teachingPlace = teachingPlace == null ? "时间地点未安排" : teachingPlace;
        var subTp = '';
        if (teachingPlace.length > 20) {
            subTp = teachingPlace.substring(0, 20) + '..';
        } else {
            subTp = teachingPlace;
        }

        capacity = capacity == null ? 0 : capacity;
        firstVolunteer = firstVolunteer == null ? 0 : firstVolunteer;

        var isFullMsg = '';
        var isFullClass = 'cv-block-hide';
        if (isFull != null && isFull == '1') {
            isFullMsg = '人数已满';
            isFullClass = '';
        }
        
        var canOperate = '1';
        var notInQueue = '';
        if(inQuene === '1'){
        	canOperate = '0';
        	notInQueue = '';
        	deleteVolunteerClass = 'cv-block-hide';
        	volunteerClass = 'cv-block-hide';
        }else{
        	notInQueue = 'cv-block-hide';
        	canOperate = '1';
        }

        var isConflictMsg = '';
        var isConflictClass = 'cv-block-hide';
        var confilctDesc = '';
        if (isConflict != null && isConflict == '1') {
            isConflictMsg = '课程冲突';
            isConflictClass = '';
            confilctDesc = _data.conflictDesc;
            if (confilctDesc == null) {
                confilctDesc = '';
            }
        }

        var hasTest = _data.hasTest;
        var btnMsg = null;
        var hasTestMsg = null;
        var hasTestMsgClass = 'cv-block-hide';
        if (hasTest != null && hasTest == '1') {
            btnMsg = '确认';// + window.CVParams.sykbs;
            hasTestMsg = '包含' + window.CVParams.sykbs;
            hasTestMsgClass = '';
        } else {
            btnMsg = '确认';
            hasTestMsg = '';
        }
        var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
        var bookContent = '';
//        if(bookParam.canSelectBook == '1'){
//        	bookContent = '<div class="bh-switch"><label class="bh-switch-label">是否订购教材</label><input type="checkbox" checked="checked" id="sfbook_' + tcId + '"><label class="bh-switch-helper"></label></div>';
//        }else{
        	bookContent = '确认选择？';
//        }
        var bookDetail = '';
        if(bookParam.needBook == '1'){
        	bookDetail += '<div class="cv-caption-text">教材订购：';
        	if(_data.needBook == '1'){
        		bookDetail += '已订购';
        	}else if(_data.needBook == '5'){
        		bookDetail += '订购部分';
        	}else{
        		bookDetail += '未订购';
        	}
        	if(_data.needOrderBook == '1'){
            	bookDetail += '<button class="cv-btn cv-btn-cancel cv-jcDetail" type="button" tcid="' + _data.teachingClassID + '" style="margin-left:10px">教材信息</button>';
        	}else{
            	bookDetail += '<button class="cv-btn cv-btn-cancel cv-jcDetail" disabled type="button" tcid="' + _data.teachingClassID + '" style="margin-left:10px">教材信息</button>';
        	}
        	bookDetail += '</div>';
        }

        var teachCampus = _data.teachCampus?_data.teachCampus:'';
        var campus = _data.teachCampus?_data.campus:'';
        var retakeTypeDetail = _data.retakeTypeDetail?_data.retakeTypeDetail:'';
        var retakeType = _data.retakeType?_data.retakeType:'';
        var conflitHour = isConflict && isConflict == '1' && _data.conflictHour ? '冲突学时:'+_data.conflictHour+' 冲突比例:' + _data.conflictHourRate : '';
        return template.replace('@teacher', teacher)
        	.replace(/@capacitySuffix/g, capacitySuffix)
            .replace('@subTeacher', subTeacher)
            .replace('@teachingPlace', teachingPlace)
            .replace('@time', subTp)
            .replace('@capacityOfMale', capacityOfMale)
            .replace('@capacityOfFemale', capacityOfFemale)
            .replace('@capacity', capacity)
            .replace('@remainingCapacityId', tcId + '_capacity')
            .replace('@remainingCapacity', remainingCapacity)
            .replace(/@volunteerText/g, volunteerText)
            .replace('@volunteerClass', volunteerClass)
            .replace('@deleteVolunteerClass', deleteVolunteerClass)
            .replace('@tcId', tcId)
            .replace('@detailId', tcId)
            .replace('@delTcId', tcId)
            .replace('@courseNumber', courseNumber)
            .replace('@isChoose', isChoose)
            .replace('@canSelect', canSelect)
            .replace('@isFull', isFull)
            .replace('@isFullMsg', isFullMsg)
            .replace('@isFullClass', isFullClass)
            .replace('@isConflict', isConflict)
            .replace('@isConflictMsg', isConflictMsg)
            .replace('@isConflictClass', isConflictClass)
            .replace('@confilctDesc', confilctDesc)
            .replace('@limitGender', limitGender)
            .replace('@numberOfMale', numberOfMale)
            .replace('@numberOfFemale', numberOfFemale)
            .replace('@hasTestMsgClass', hasTestMsgClass)
            .replace('@hasTestMsg', hasTestMsg)
            .replace('@hasTest', hasTest)
            .replace('@hasBook', _data.hasBook)
            .replace('@btnMsg', btnMsg)
            .replace('@hasCourseUrl', hasCourseUrl)
            .replace('@courseUrl', courseUrl)
            .replace('@canOperate', canOperate)
            .replace('@notInQueue', notInQueue)
            .replace('@bookContent', bookContent)
            .replace('@bookDetail', bookDetail)
            .replace('@teachCampus', teachCampus)
            .replace('@campus', campus)
            .replace('@retakeTypeDetail', retakeTypeDetail)
            .replace('@retakeType', retakeType)
            .replace('@conflictHour', conflitHour)
            .replace('@courseDiv', tcId + "_courseDiv");
    }
})(window.CVCourseCard = window.CVCourseCard || {});

/**
 * 课表列表
 */
;
(function(_list) {
    /**
     * 列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {object}
     * @param _data.type {string} 要初始化的类型,recommend推荐选课,public公选课
     * @param _data.data {object} 内容数据
     */
    _list.init = function($dom, _data) {
        init($dom, _data);
        eventsListen($dom);
    };

    _list.openRow = function($row) {
        openCourseTeacherList($row);
    };

    _list.reload = function($dom, _data, needAppendFlag) {
        var type = _data.type;
        if (type === 'recommend') {
            recommendReload($dom, _data.data);
        } else if (type === 'public') {
            publicReloda($dom, _data.data, needAppendFlag);
        } else if (type === 'program') {
            programReload($dom, _data.data);
        } else if (type === 'unProgram') {
            unProgramReload($dom, _data.data);
        } else if (type === 'retake') {
            retakeReload($dom, _data.data);
        } else if (type === 'sport') {
            sportReload($dom, _data.data);
        } else if (type === 'minor') {
            minorReload($dom, _data.data);
        } else if (type === 'school') {
            schoolReload($dom, _data.data);
        }
    };

    /**
     * 事件监听
     * @param $dom
     */
    function eventsListen($dom) {
        //点击每行的事件
        $dom.children('.cv-list.recommend-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));
        });
        $dom.children('.cv-list.program-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));
        });
        $dom.children('.cv-list.unprogram-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));            
        });
        $dom.children('.cv-list.retake-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));
        });
        $dom.children('.cv-list.sport-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));
        });
        $dom.children('.cv-list.minor-list').on('click', '.cv-row', function() {
            selectIndex = $(this).attr('index');
            openCourseTeacherList($(this));
        });
        //点击校公选课选择按钮事件
        $dom.children('.cv-list.public-list').on('click', '.cv-choice', function(e) {
        	var $this = $(e.currentTarget);
        	if($this.hasClass('cv-disabled')){
        		return false;
        	}
            var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
            var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
            var electiveBatch = studentInfo.electiveBatch;
            //若未开放，则重新请求是否开放
            if(!electiveIsOpen || electiveIsOpen != '1'){
            	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
        		if(resp.msg == '1'){
        			sessionStorage.setItem('electiveIsOpen', '1');
        			electiveIsOpen = '1';
        		}
            }
            //判断是否开放
            if (!electiveIsOpen || electiveIsOpen != '1') {
            	$.bhTip({
        			content: '轮次未开放',
        			state: 'danger'
        		});
            	return false;
            }
        	// 是否冲突
            if(!checkIsConflict($this)){
            	return false;
            }
        	checkSfkxqSelect($this, function(){
        		selectPublicCourse(e, 'public');
        	});    
        });
        
        //点击校公选课详情按钮事件
        $dom.children('.cv-list.public-list').on('click', '.cv-jxbdetail', function(e) {
        	var jxbid = $(e.currentTarget).attr('tcid');
        	jxbInfoWindow(jxbid, $(e.currentTarget).attr('data-courseUrl'));
        });
        
        //点击课程跳转新页面
        $dom.children('.cv-list.recommend-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.program-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.unprogram-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);         
        });
        $dom.children('.cv-list.retake-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.sport-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.minor-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
            var courseNum = $(this).attr('data-num');
            window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.public-list').on('click', '.cv-detail', function(e) {
        	e.stopPropagation();
        	var courseNum = $(this).attr('data-num');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/coursedetail.do?courseNum=' + courseNum);
        });
        $dom.children('.cv-list.public-list').on('click', '.cv-jcDetail', function(e) {
        	var jxbid = $(e.currentTarget).attr('tcid');
        	window.open(BaseUrl + '/sys/xsxkapp/*default/jcdetail.do?jxbid=' + jxbid);
        });
        
        //查看所属方案
        $dom.children('.cv-list.unprogram-list').on('click', '.cv-faDetail', function(e) {
        	e.stopPropagation();
        	CVSyfaList.init($(this).attr('data-num'));
        });
    }
    
    function checkSfkxqSelect($this, callback){
    	if($this.hasClass('cv-disabled')){
    		return false;
    	}
    	var resultFlag = '0';
    	var title = '';
    	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    	if(sysParam.canSelectALLKC == '1'){
    		var campus = $this.attr('campus');
    		var teachCampus = $this.attr('teachcampus');
    		if(studentInfo.electiveBatch.multiTeachCampus == 1){
    			//允许夸教学区
    			if(studentInfo.electiveBatch.multiCampus == 1){
    				//允许夸校区
    				if(teachCampus != studentInfo.teachCampus){
    					resultFlag = '1';
        				title = '确定跨教学区选课？';
        			}else if(campus != studentInfo.campus){
        				resultFlag = '1';
        				title = '确定跨校区选课？';
        			}
    			}else {
    				//不允许夸校区
    				if(campus != studentInfo.campus){
    					resultFlag = '2';
    					title = '不允许跨校区选课！';
    				}else if(teachCampus != studentInfo.teachCampus){
    					resultFlag = '1';
        				title = '确定跨教学区选课？';
    				}
    			}
    		}else{
    			//不允许夸教学区
    			if(teachCampus != studentInfo.teachCampus){
    				resultFlag = '2';
					title = '不允许跨校区选课';
    			}else{
    				if(studentInfo.electiveBatch.multiCampus == 1){
        				//允许夸校区
        				if(campus != studentInfo.campus){
        					resultFlag = '1';
            				title = '确定跨校区选课？';
            			}
        			}else {
        				//不允许夸校区
        				if(campus != studentInfo.campus){
        					resultFlag = '2';
        					title = '不允许跨校区选课!';
        				}
        			}
    			}
    		}
    	}
    	var dialogData = {};
		if(resultFlag == '1'){
			dialogData = {
				title: '提示',
				content: title,
				callback: callback
			};
			CVDialog.showWarning(dialogData);
		}else if(resultFlag == '2'){
			dialogData = {
				title: '警告',
				content: title
			};
			CVDialog.showDanger(dialogData);
		}else {
			callback();
		}
    }
    
    function selectPublicCourse(e, type){
    	var $this = $(e.currentTarget);
    	if($this.hasClass('cv-disabled')){
    		return false;
    	}
        var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
        //若未开放，则重新请求是否开放
        if(!electiveIsOpen || electiveIsOpen != '1'){
        	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
    		if(resp.msg == '1'){
    			sessionStorage.setItem('electiveIsOpen', '1');
    			electiveIsOpen = '1';
    		}
        }
        //判断是否开放
        if (!electiveIsOpen || electiveIsOpen != '1') {
        	$.bhTip({
    			content: '轮次未开放',
    			state: 'danger'
    		});
        	return false;
        }
        var title = '';
        var addType = '';
        if(type == 'public'){
    		title = '校公选课';
    		addType = 'addPublic';
    		var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
            if(sysParam.xgxkQueryTitle){
            	title = sysParam.xgxkQueryTitle;
            }
		}
        var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
        window.cardOperateBtn = $this;
        if($this.attr('hasTest') == '1'){
        	if(bookParam.canSelectBook == '1' && bookParam.canSelectBook == '1' && $this.attr('hasBook')=='1'){
        		CVDialog.showPublicBookWidthTest($this.attr('tcId'), $this.attr('capacitySuffix'), addType);
            }else{
            	CVTestCourse.initCourse($this.attr('tcId'), $this.attr('capacitySuffix'));
            }
        }else{
        	if(bookParam.canSelectBook == '1' && bookParam.canSelectBook == '1' && $this.attr('hasBook')=='1'){
        		CVDialog.showPublicBookWidthTest($this.attr('tcId'), $this.attr('capacitySuffix'), addType);
        		//CVDialog.showPublicBook(e, addType);
            }else{
            	var addDialogObj = new Object();
            	addDialogObj.title = '确认选择？';
            	addDialogObj.content = '确认选择这门' + title + '？';
            	CVDialog.show(addDialogObj, e, addType);
            }
        }
    }
    
    /**
     * 弹出教学班信息
     */
    function jxbInfoWindow(jxbid, courseUrl){
    	var html = $('#tpl-jxbDetail-model').html();
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
    	queryJxbInfo(electiveBatch.code, jxbid).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
            	var teacherTpl = '';
            	var tplArr = [];
            	if(!!resp.data.teacherNameList){
            		var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
            		var customTeachingInfo = sysParam.customTeachingInfo;
            		var teachers = resp.data.teacherNameList.split(',');
            		if(customTeachingInfo == "1"){
            			$.each(teachers, function(tcIndex, tcStr){
                    		tplArr = tcStr.split('|');
                    		if(tplArr.length > 2 && tplArr[2] != null && tplArr[2] != '' && tplArr[2] != undefined){
                    			teacherTpl += '<a class="jsSimple" data-jsh="'+ tplArr[1] + '" href="javascript:void(0)">' + tplArr[0] + '</a> <a class="url" href="' + tplArr[2] + '" target="_blank">[教师主页]</a>';
                    		}else{
                    			teacherTpl += '<a class="jsSimple" data-jsh="'+ tplArr[1] + '" href="javascript:void(0)">' + tplArr[0] + '</a>';
                    		}
                    	});
            		}else{
            			$.each(teachers, function(tcIndex, tcStr){
                    		tplArr = tcStr.split('|');
                    		if(tplArr[2] != null && tplArr[2] != '' && tplArr[2] != undefined){
                    			teacherTpl += '<a href="' + tplArr[2] + '" target="_blank">' + tplArr[0] + '</a>';
                    		}else{
                    			teacherTpl += '<a target="_blank">' + tplArr[0] + '</a>';
                    		}
                    		
                    	});
            		}
                	
            	}else{
            		teacherTpl = '无上课老师';
            	}
            	var tjbjxx = resp.data.recommendSchoolClass?resp.data.recommendSchoolClass:'无推荐班级';
            	var jxbxx = resp.data.extInfo?resp.data.extInfo:'无教学班信息';
            	var kssj = resp.data.examTime; //考试时间数据
            	var display = 'block';
            	if(!kssj || electiveBatch.noCheckExamTime=='1'){
            		display = 'none';
            	}
            	var courseDisplay = 'block';
            	if(!courseUrl){
            		courseDisplay = 'none';
            	}
            	html = html.replace(/@jsxx/g, teacherTpl)
            		.replace(/@tjbjxx/g, tjbjxx)
                	.replace(/@jxbxx/g, jxbxx)
                	.replace(/@display/g, display)
                	.replace(/@kssj/g, electiveBatch.noCheckExamTime=='1'?'-':kssj)
                	.replace(/@courseDisplay/g, courseDisplay)
                	.replace(/@courseUrl/g, courseUrl);
            	
            	BH_UTILS.bhWindow(html, '教学班详情',[
                         {
                             text:'关闭',className:'cv-btn bh-btn-default self-line-height',
                             callback:function(){
                             }
                         }
                     ], {
            		width: 950,
                    height: 600
                 });
            	
            	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
            	$('.jsSimple').on('click', function(event){
            		event.stopPropagation();
            		var jsh = $(event.currentTarget).attr('data-jsh');
            		if(!sysParam.customTeachingPage){
            			window.open(BaseUrl + '/sys/xsxkapp/*default/jssimple.do?jsh=' + jsh);
            		}else{
            			window.open(BaseUrl + '/sys/xsxkapp/*default/jssimple1.do?jsh=' + jsh);
            		}
            	});
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectProgramCourse').html(resp.msg);
            }
        });
    }
    

    /**
     * 打开该课程的开课老师列表
     * @param $row 行对象
     */
    function openCourseTeacherList($row) {
        var isOpen = $row.attr("isOpen");
        if (isOpen != null && isOpen == "1") {
            // 展开状态，收起节点
            $row.attr("isOpen", "0");
            $row.removeClass('cv-expand');
            selectIndex = null;
        } else {
            // 收起状态，展开节点
            $row.attr("isOpen", "1");
            var jxbList = courseDataList[$row.attr("index")].tcList;
            if (jxbList != null && jxbList.length > 0) {
                var html = '';
                for (var i = 0, len = jxbList.length; i < len; i++) {
                    html += CVCourseCard.getHtml(jxbList[i]);
                }
                if ($row.children('section').length === 0) {
                    $row.addClass('cv-expand').append('<section>' + html + '</section>');

                    //点击卡片
                    $row.on('click', '.cv-course-card', function(e) {
                        var $this = $(e.currentTarget);
                        var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
                        var electiveBatch = studentInfo.electiveBatch;
                        //若未开放，则重新请求是否开放
                        if(electiveIsOpen == null || electiveIsOpen != '1'){
                        	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
                    		if(resp.msg == '1'){
                    			sessionStorage.setItem('electiveIsOpen', '1');
                    			electiveIsOpen = '1';
                    		}
                        }
                        //判断是否开放
                        if (electiveIsOpen != null && electiveIsOpen == '1') {
                        	// 是否可操作
                            var canOperate = $this.attr('canOperate');
                            if (canOperate != '1') {
                            	e.stopPropagation();
                            	return;
                            }
                        	// 是否选择
                            var isChoose = $this.parent().parent().attr('isChoose');
                            if (isChoose != '0') {
                                e.stopPropagation();
                                return;
                            }
                            // 是否已满
                            var isFull = $this.attr('isFull');
                            var tcType = sessionStorage.getItem("teachingClassType");
                            var retakeNoCheckClassCapacity = electiveBatch.retakeNoCheckClassCapacity;
                            if (tcType == 'CXKC' && isFull == '1' && retakeNoCheckClassCapacity == '0') {
                                e.stopPropagation();
                                return;
                            } else if (tcType != 'CXKC' && isFull == '1') {
                                e.stopPropagation();
                                return;
                            }
                            // 男、女人数是否已满
                            var limitGender = $this.attr('limitGender');
                            if (limitGender != null && limitGender == '1') {
                                var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
                                var gender = studentInfo.gender;
                                if (gender != null && gender == '1') {
                                    // 男生
                                    var capacityOfMale = $this.attr('capacityOfMale');
                                    var numberOfMale = $this.attr('numberOfMale');
                                    if ((capacityOfMale != null && numberOfMale != null) && (parseInt(numberOfMale) + 1 > parseInt(capacityOfMale))) {
                                        $.bhTip({
                                            content: '男生人数超过上限',
                                            state: 'warning'
                                        });
                                        e.stopPropagation();
                                        return;
                                    }
                                } else {
                                    // 女生
                                    var capacityOfFemale = $this.attr('capacityOfFemale');
                                    var numberOfFemale = $this.attr('numberOfFemale');
                                    if ((capacityOfFemale != null && numberOfFemale != null) && (parseInt(numberOfFemale) + 1 > parseInt(capacityOfFemale))) {
                                        $.bhTip({
                                            content: '女生人数超过上限',
                                            state: 'warning'
                                        });
                                        e.stopPropagation();
                                        return;
                                    }
                                }                                
                            }
                            // 是否冲突
                            if(!checkIsConflict($this)){
                            	return false;
                            }
                            checkSfkxqSelect($this.find('.cv-btn-chose'), function(){
                            	showCourseCardOperate($(e.currentTarget));
                            });
                        }
                        e.stopPropagation();                        
                    });
                    //点击取消按钮,显示开课老师信息
                    $row.on('click', '.cv-btn-cancel', function(e) {
                        showCourseCardInfo($(this).closest('.cv-course-card'));
                        e.stopPropagation();
                    });

                    //点击选择按钮,添加志愿选课
                    $row.on('click', '.cv-btn-chose', function(e) {
                    	var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
                        var electiveBatch = studentInfo.electiveBatch;
                        //若未开放，则重新请求是否开放
                        if(!electiveIsOpen || electiveIsOpen != '1'){
                        	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
                    		if(resp.msg == '1'){
                    			sessionStorage.setItem('electiveIsOpen', '1');
                    			electiveIsOpen = '1';
                    		}
                        }
                        //判断是否开放
                        if (!electiveIsOpen || electiveIsOpen != '1') {
                        	$.bhTip({
                    			content: '轮次未开放',
                    			state: 'danger'
                    		});
                        	return false;
                        }
                        var $this = $(e.currentTarget);
                        var $card = $(this).closest('.cv-course-card');
                        var $row = $(this).closest('.cv-row');
                        
                        showCourseCardInfo($card);
                        e.stopPropagation();
                        var tcId = $this.attr('tcId');
                        var capacitySuffix = $this.attr('capacitySuffix');
                        var hasBook = $this.attr('hasBook');
                        var hasTest = $this.attr('hasTest');
                        var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
                        if ((hasTest != null && hasTest == '1') || (bookParam.canSelectBook=='1' && hasBook != null && hasBook == '1')) {
                            // 有实验课程
                        	window.cardOperateBtn = $this;
                            CVTestCourse.initCourse(tcId, capacitySuffix);
                        } else {
                            // 无实验课程
                            var addParam = buildAddVolunteerParam(tcId);
                            addVolunteer(addParam).done(function(resp) {
                                var code = resp.code;
                                if (code != null && code == '1') {
                                    initProcessInterval(function(processResp){
                                    	if(processResp.code == '1'){
                                    		$.bhTip({
                                    			content: '添加选课成功',
                                    			state: 'success'
                                    		});
                                    		$row.addClass('cv-active').attr('ischoose', '1');
                                    		$card.attr('ischoose', '1');
                                    		$card.find('.cv-select-flag').removeClass('cv-block-hide').addClass('cv-one').html('已选');
                                    		$card.find('.cv-delete-volunteer').removeClass('cv-block-hide');
                                    		flushTeachingClassCapacity(tcId, capacitySuffix);
                                    		// 查询已选课程数量
                                    		querySelectCourseNum();
                                    	}else if(processResp.code == '-1'){
                                    		$.bhTip({
                                    			content: processResp.msg,
                                    			state: 'danger'
                                    		});
                                    	}
                                    });
                                } else if (code == '302') {
                                    sessionStorage.removeItem('token');
                                    sessionStorage.removeItem('studentInfo');
                                    window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
                                } else {
                                    var failObj = new Object();
                                    failObj.title = '失败';
                                    failObj.content = resp.msg;
                                    CVDialog.showDanger(failObj);
                                }
                            });
                        }                        
                    });

                    // 点击删除志愿按钮事件
                    $('.cv-delete-volunteer').on('click', function(e) {
                    	var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
                        var electiveBatch = studentInfo.electiveBatch;
                        //若未开放，则重新请求是否开放
                        if(!electiveIsOpen || electiveIsOpen != '1'){
                        	var resp = queryXklcSfkfBySync({xklcdm: electiveBatch.code});
                    		if(resp.msg == '1'){
                    			sessionStorage.setItem('electiveIsOpen', '1');
                    			electiveIsOpen = '1';
                    		}
                        }
                        //判断是否开放
                        if (!electiveIsOpen || electiveIsOpen != '1') {
                        	$.bhTip({
                    			content: '轮次未开放',
                    			state: 'danger'
                    		});
                        	return false;
                        }
                        var dialogData = new Object();
                        dialogData.title = '确认退选';
                        dialogData.content = '确认退选这门课程吗？';
                        CVDialog.show(dialogData, e, 'delSelectCourse');
                    });
                    
                    // 点击教材详情事件
                    $('.cv-jcDetail').on('click', function(e) {
                    	var jxbid = $(e.currentTarget).attr('tcid');
                    	window.open(BaseUrl + '/sys/xsxkapp/*default/jcdetail.do?jxbid=' + jxbid);
                    });
                    
                    // 点击教学班详情事件
                    $('.cv-jxbDetail').on('click', function(e) {
                    	var jxbid = $(e.currentTarget).attr('tcid');
                    	jxbInfoWindow(jxbid, $(e.currentTarget).attr('data-courseUrl'));
                    });
                    
                } else {
                    $row.addClass('cv-expand');
                }
            } else {
                if ($row.children('section').length === 0) {
                    $row.addClass('cv-expand').append('<section>没有教学班</section>');
                } else {
                    $row.addClass('cv-expand');
                }
            }
        }
    }

    /**
     * 显示开课老师信息
     * @param $card
     */
    function showCourseCardInfo($card) {
        $card.removeClass('cv-setting');
    }

    /**
     * 进入志愿选择项
     * @param $card
     */
    function showCourseCardOperate($card) {
        $card.addClass('cv-setting');
    }

    /**
     * 列表初始化
     * @param $dom 要初始化的容器对象
     * @param _data
     * @param _data.type 要初始化的类型,recommend推荐选课,public公选课
     * @param _data.data 内容数据
     */
    function init($dom, _data) {
        var type = _data.type;
        var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        if (type === 'recommend') {
            recommendInit($dom, _data.data);
            CVTitleMode.titleInit($('#recommendSpan'));
            $('#recommendTitle').html(sysParam.displayNameTJKC);
        } else if (type === 'public') {
            publicInit($dom, _data.data);
            CVTitleMode.titleInit($('#publicSpan'));
            $('#publicTitle').html(sysParam.displayNameXGXK);
        } else if (type === 'program') {
            programInit($dom, _data.data);
            CVTitleMode.titleInit($('#programSpan'));
            $('#programTitle').html(sysParam.displayNameFANKC);
        } else if (type === 'unProgram') {
            unProgramInit($dom, _data.data);
            CVTitleMode.titleInit($('#unProgramSpan'));
            $('#unProgramTitle').html(sysParam.displayNameFAWKC);
        } else if (type === 'retake') {
            retakeInit($dom, _data.data);
            CVTitleMode.titleInit($('#retakeSpan'));
            $('#retakeTitle').html(sysParam.displayNameCXKC);
        } else if (type === 'sport') {
            sportInit($dom, _data.data);
            CVTitleMode.titleInit($('#sportSpan'));
            $('#sportTitle').html(sysParam.displayNameTYKC);
        } else if (type === 'minor') {
            minorInit($dom, _data.data);
            CVTitleMode.titleInit($('#minorSpan'));
            $('#minorTitle').html(sysParam.displayNameFXKC);
        } else if (type == 'school') {
            schoolInit($dom, _data.data);
            CVTitleMode.titleInit($('#schoolSpan'));
        }
    }

    /**
     * 推荐选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function recommendInit($dom, _data) {
        var wrapTemplate = $('#tpl-recommend-list').html();
        var rowTemplate = $('#tpl-recommend-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', recommendTotalPage)
                .replace("@pageNumber", recommendPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#recommendUp").on("click", function(e) {
                pagingCourse('up', 'recommend');
            });
            $("#recommendDown").on("click", function(e) {
                pagingCourse('down', 'recommend');
            });
            // 绑定排序事件
            $("#recommendSort").on("click", function(e) {
                expertModeSorting(e, 'recommend');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 推荐选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function recommendReload($dom, _data) {
        var rowTemplate = $('#tpl-recommend-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            //var noDataHtml = '<div style="height:50px"><h4>没有数据</h4></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#recommendTotalPage').html(recommendTotalPage);
        $('#recommendPageNumber').html(recommendPageNumber + 1);
    }

    /**
     * 辅修选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function minorInit($dom, _data) {
        var wrapTemplate = $('#tpl-minor-list').html();
        var rowTemplate = $('#tpl-minor-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', minorTotalPage)
                .replace("@pageNumber", minorPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#minorUp").on("click", function(e) {
                pagingCourse('up', 'minor');
            });
            $("#minorDown").on("click", function(e) {
                pagingCourse('down', 'minor');
            });
            // 绑定排序事件
            $("#minorSort").on("click", function(e) {
                expertModeSorting(e, 'minor');
            });
        } else {
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 辅修选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function minorReload($dom, _data) {
        var rowTemplate = $('#tpl-minor-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#minorTotalPage').html(minorTotalPage);
        $('#minorPageNumber').html(minorPageNumber + 1);
    }

    /**
     * 重修课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function retakeInit($dom, _data) {
        var wrapTemplate = $('#tpl-retake-list').html();
        var rowTemplate = $('#tpl-retake-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', retakeTotalPage)
                .replace("@pageNumber", retakePageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#retakeUp").on("click", function(e) {
                pagingCourse('up', 'retake');
            });
            $("#retakeDown").on("click", function(e) {
                pagingCourse('down', 'retake');
            });
            // 绑定排序事件
            $("#retakeSort").on("click", function(event) {
                expertModeSorting(event, 'retake');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 重修选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function retakeReload($dom, _data) {
        var rowTemplate = $('#tpl-retake-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            //var noDataHtml = '<div style="height:50px"><h4>没有数据</h4></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#retakeTotalPage').html(retakeTotalPage);
        $('#retakePageNumber').html(retakePageNumber + 1);
    }

    /**
     * 体育选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function sportInit($dom, _data) {
        var wrapTemplate = $('#tpl-sport-list').html();
        var rowTemplate = $('#tpl-sport-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', sportTotalPage)
                .replace("@pageNumber", sportPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#sportUp").on("click", function(e) {
                pagingCourse('up', 'sport');
            });
            $("#sportDown").on("click", function(e) {
                pagingCourse('down', 'sport');
            });
            // 绑定排序事件
            $("#sportSort").on("click", function(event) {
                expertModeSorting(event, 'sport');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 体育选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function sportReload($dom, _data) {
        var rowTemplate = $('#tpl-sport-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            //var noDataHtml = '<div style="height:50px"><h4>没有数据</h4></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#sportTotalPage').html(sportTotalPage);
        $('#sportPageNumber').html(sportPageNumber + 1);
    }

    /**
     * 方案内选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function programInit($dom, _data) {
        var wrapTemplate = $('#tpl-program-list').html();
        var rowTemplate = $('#tpl-program-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', programTotalPage)
                .replace("@pageNumber", programPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#programUp").on("click", function(e) {
                pagingCourse('up', 'program');
            });
            $("#programDown").on("click", function(e) {
                pagingCourse('down', 'program');
            });
            // 绑定排序事件
            $("#programSort").on("click", function(event) {
                expertModeSorting(event, 'program');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 方案内选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function programReload($dom, _data) {
        var rowTemplate = $('#tpl-program-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            //var noDataHtml = '<div style="height:50px"><h4>没有数据</h4></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#programTotalPage').html(programTotalPage);
        $('#programPageNumber').html(programPageNumber + 1);
    }

    /**
     * 方案外选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     */
    function unProgramInit($dom, _data) {
        var wrapTemplate = $('#tpl-unprogram-list').html();
        var rowTemplate = $('#tpl-unprogram-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', unProgramTotalPage)
                .replace("@pageNumber", unProgramPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#unProgramUp").on("click", function(e) {
                pagingCourse('up', 'unProgram');
            });
            $("#unProgramDown").on("click", function(e) {
                pagingCourse('down', 'unProgram');
            });
            // 绑定排序事件
            $("#unProgramSort").on("click", function(event) {
                expertModeSorting(event, 'unProgram');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    /**
     * 方案外选课列表数据重载
     * @param $dom {jQuery} 要重载的容器对象
     * @param _data {Array} 重载数据列表
     */
    function unProgramReload($dom, _data) {
        var rowTemplate = $('#tpl-unprogram-list-row').html();
        var html = buildCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            //var noDataHtml = '<div style="height:50px"><h4>没有数据</h4></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#unProgramTotalPage').html(unProgramTotalPage);
        $('#unProgramPageNumber').html(unProgramPageNumber + 1);
    }

    /**
     * 创建课程列表html
     * @param template {jQuery} html模板
     * @param _data    {Array}  课程列表数据
     */
    function buildCourseListHtml(template, _data) {
        var html = '';
        var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        var hascourseDetail = 'block';
        if(sysParam.noDisplayCourseURL == '1'){
        	hascourseDetail = 'none';
        }
        if (_data != null && _data.length > 0) {
            var dataItem = null;
            for (var i = 0, length = _data.length; i < length; i++) {
                dataItem = _data[i];
                var number = dataItem.courseNumber;
                var title = dataItem.courseName;
                var _class = dataItem.number;
                var type = dataItem.typeName;
                var nature = dataItem.courseNatureName;
                var department = dataItem.departmentName;
                var majorFlag = dataItem.majorFlag?dataItem.majorFlag:'';
                var courseFlag = dataItem.courseFlag;
                var courseFlagDisplay = 'cv-hide';
                if(courseFlag){
                	courseFlagDisplay = 'cv-show';
                }else{
                	courseFlag = '';
                }
                
                var credit = dataItem.credit;
                var selectedClass = dataItem.selected ? 'cv-active' : '';
                var isChoose = dataItem.selected ? '1' : '0';
                var cxxklx = dataItem.retakeTypeDetail?window.CVParams.cxxklx[dataItem.retakeTypeDetail]:'';
                // 处理数据为null的问题
                number = number == null ? 0 : number;
                title = title == null ? '-' : title;
                type = type == null ? '-' : type;
                nature = nature == null ? '-' : nature;
                department = department == null ? '-' : department;

                var cxkcCode = (dataItem.replaceCourseName && dataItem.replaceCourseName!==number)? dataItem.replaceCourseName:'';
                var hasCxkc = cxkcCode? 'block' : 'none';
                
                html += template.replace('@number', number)
                	.replace('@courseFlagDisplay', courseFlagDisplay)
                	.replace('@courseFlag', courseFlag)
                	.replace('@courseNumber', number)
                    .replace('@jxbNumber', number)
                    .replace('@jxb1Number', number)
                    .replace('@hascourseDetail', hascourseDetail)
                    .replace('@title', title)
                    .replace('@class', _class)
                    .replace('@type', type)
                    .replace('@nature', nature)
                    .replace('@department', department)
                    .replace('@majorFlag', majorFlag)
                    .replace('@credit', credit)
                    .replace('@selectedClass', selectedClass)
                    .replace('@index', i)
                    .replace('@cxxklx', cxxklx)
                    .replace('@isChoose', isChoose)
                    .replace('@hasCxkc',hasCxkc)
                    .replace('@cxkcCode',cxkcCode);
            }
        } else {

        }
        return html;
    }

    /**
     * 公选课列表初始化
     * @param $dom {jQuery} 要初始化的容器对象
     * @param _data {Array}
     * @param _data.number {string} 课程编号
     * @param _data.title {string} 课程名称
     * @param _data.teacher {string} 上课教师
     * @param _data.time {string} 上课时间
     * @param _data.capacity {string} 课容量
     * @param _data.firstVolunteer {number} 已报第一志愿
     * @param _data.type {string} 课程类型
     * @param _data.address {string} 上课地点
     * @param _data.hours {number} 学时
     * @param _data.credit {number} 学分
     * @param _data.volunteerIndex {number} 选择的志愿,0未选择,1第一志愿,2第二志愿,3第三志愿,4第四志愿,5第五志愿
     */
    function publicInit($dom, _data) {
        var wrapTemplate = $('#tpl-public-list').html();
        var rowTemplate = $('#tpl-public-list-row').html();
        var jcdgShow = 'cv-hide';
        var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
        if(bookParam.needBook == '1'){
        	jcdgShow = 'cv-show';
        }
        var html = buildPublicCourseListHtml(rowTemplate, _data);
        if (html != null && html.length > 0) {
            wrapTemplate = wrapTemplate.replace('@body', html)
            	.replace('@jcdgShow', jcdgShow)
                .replace('@totalPage', publicTotalPage)
                .replace("@pageNumber", publicPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#publicUp").on("click", function(e) {
                pagingCourse('up', 'public');
            });
            $("#publicDown").on("click", function(e) {
                pagingCourse('down', 'public');
            });
            // 绑定排序事件
            $("#publicSort").on("click", function(event) {
                expertModeSorting(event, 'public');
            });
        } else {
            //var html = '<div style="height:50px"><h4>没有数据</h4></div>';
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
            	.replace('@jcdgShow', jcdgShow)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    function publicReloda($dom, _data, needAppendFlag) {
        var rowTemplate = $('#tpl-public-list-row').html();
        var html = buildPublicCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
        	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
            if(sysParam.xgxkNotPage == '1' && needAppendFlag){
            	$dom.append(html);
            }else{
            	$dom.html(html);
            }
        } else {
            //var noDataHtml = '<div align="center"><p>没有数据</p></div>';
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#publicTotalPage').html(publicTotalPage);
        $('#publicPageNumber').html(publicPageNumber + 1);
    }

    function buildPublicCourseListHtml(template, _data) {
        var html = '';
        var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        var hascourseDetail = 'block';
        var nocourseDetail = 'none';
        if(sysParam.noDisplayCourseURL == '1'){
        	hascourseDetail = 'none';
        	nocourseDetail = 'block';
        }
        var jcdgShow = 'cv-hide';
        var bookParam = JSON.parse(sessionStorage.getItem('bookParam'));
        if(bookParam.needBook == '1'){
        	jcdgShow = 'cv-show';
        }
        if (_data != null && _data.length > 0) {
            var dataItem = null;
            for (var i = 0, length = _data.length; i < length; i++) {
                dataItem = _data[i];
                var tcId = dataItem.teachingClassID;
                var hasTest = dataItem.hasTest;
                var number = dataItem.courseNumber;
                var numberTitle = number;
                if (number != null && number.length > 12) {
                    number = number.substring(0, 10) + '...';
                }

                var courseUrl = dataItem.courseUrl?dataItem.courseUrl:'';
                var hasCourseUrl = 0;
                if(courseUrl){
                	hasCourseUrl = 1;
                }
                
                var index = dataItem.courseIndex;

                var title = dataItem.courseName;
                title = title == null ? '-' : title;

                var teacher = dataItem.teacherName;
                teacher = teacher == null ? '-' : teacher;

                var timeTitle = dataItem.teachingPlace;
                var time = null;
                if (dataItem.teachingPlace != null) {
                    time = dealTeachingPlace(dataItem.teachingPlace);
                }
                time = time == null ? '-' : time;
                timeTitle = timeTitle == null ? '' : timeTitle;
                
                var capacity = dataItem.classCapacity;
                capacity = capacity == null ? 0 : capacity;

                var firstVolunteer = dataItem.numberOfFirstVolunteer;
                firstVolunteer = firstVolunteer == null ? 0 : firstVolunteer;
                
                if (parseInt(firstVolunteer) >= parseInt(capacity)) {
                    firstVolunteer = '<button class="cv-btn cv-tag cv-danger" type="button">人数已满</button>';
                }

                var publicCourseTypeName = dataItem.publicCourseTypeName;
                publicCourseTypeName = publicCourseTypeName == null ? '-' : publicCourseTypeName;

                var hours = dataItem.hours;
                var credit = dataItem.credit;
                var capacitySuffix = dataItem.capacitySuffix;
                var volunteerText = '';
                var selectedClass = '';

                var isFull = dataItem.isFull;
                if (isFull == '1') {
                    title = title + '<span style="color:#CC0000">[已满]</span>';
                }
                var isConflict = dataItem.isConflict;
                var conflictDesc = dataItem.conflictDesc;
                if (conflictDesc == null) {
                    conflictDesc = "";
                }
                if (isConflict == '1') {
                    title = title + '<span style="color:#CC0000" title="' + conflictDesc + '">[冲突]</span>';
                }

                var isChoose = dataItem.isChoose;
                if (isChoose != null && isChoose == '1') {
                    volunteerText = '已选';
                    selectedClass = 'cv-one cv-selected';
                } else {
                    volunteerText = '';
                    selectedClass = '';
                }

                var isDisabled = '';
                var electiveIsOpen = sessionStorage.getItem('electiveIsOpen');
                if (electiveIsOpen != null && electiveIsOpen == '1'){
                    isDisabled = '';
                } else {
                    isDisabled = 'disabled="disabled"';
                }

                var limitGender = dataItem.limitGender;
                if (limitGender == null) {
                    limitGender = '0';
                }
                var capacityOfMale = dataItem.capacityOfMale;
                var capacityOfFemale = dataItem.capacityOfFemale;
                var numberOfMale = dataItem.numberOfMale;
                var numberOfFemale = dataItem.numberOfFemale;

                // 课程板块
                var courseSection = null;
                var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
                // 是否展示课程板块
                var displayCourseSection = sysParam.displayCourseSection;
                if (displayCourseSection != null && displayCourseSection == '1') {
                    courseSection = dataItem.courseSection;
                }
                courseSection = courseSection == null ? '' : courseSection;
                
                var courseFlag = dataItem.courseFlag;
                var courseFlagDisplay = 'cv-hide';
                if(courseFlag){
                	courseFlagDisplay = 'cv-show';
                }else{
                	courseFlag = '';
                }
                var needbook = '';
                if(bookParam.needBook == '1'){
                	if(dataItem.needBook == '1'){
                		needbook = '已订购';
                	}else{
                		needbook = '未订购';
                	}
                }
                var teachCampus = dataItem.teachCampus?dataItem.teachCampus:'';
                var campus = dataItem.teachCampus?dataItem.campus:'';
                var retakeTypeDetail = dataItem.retakeTypeDetail?dataItem.retakeTypeDetail:'';
                var retakeType = dataItem.retakeType?dataItem.retakeType:'';
                var engpName = dataItem.engpName;
                numberTitle = (numberTitle + '[' + (engpName?(index+"-"+engpName):index) + ']');
                html += template.replace('@numberTitle',numberTitle)
                    .replace('@courseNumber', number)
                    .replace('@courseFlagDisplay', courseFlagDisplay)
                    .replace('@courseFlag', courseFlag)
                    .replace('@title', title)
                    .replace('@teacher', teacher)
                    .replace('@timeTitle', timeTitle)
                    .replace('@time', time)
                    .replace('@capacityOfMale', capacityOfMale)
                    .replace('@capacityOfFemale', capacityOfFemale)
                    .replace('@capacity', capacity)
                    .replace('@firstVolunteer', firstVolunteer)
                    .replace('@type', publicCourseTypeName)
                    .replace('@hours', hours)
                    .replace('@credit', credit)
                    .replace('@volunteerText', volunteerText)
                    .replace('@selectedClass', selectedClass)
                    .replace(/@number1/g,numberTitle)
                    .replace('@number', number)
                    .replace(/@tcId/g, tcId)
                    .replace('@jxbId', tcId)
                    .replace('@isFull', isFull)
                    .replace('@isConflict', isConflict)
                    .replace('@isDisabled', isDisabled)
                    .replace('@limitGender', limitGender)
                    .replace('@numberOfMale', numberOfMale)
                    .replace('@numberOfFemale', numberOfFemale)
                    .replace('@hasTest', hasTest)
                    .replace('@courseSection', courseSection)
                    .replace('@hasCourseUrl', hasCourseUrl)
                    .replace('@courseUrl', courseUrl)
                    .replace('@capacitySuffix', capacitySuffix)
                    .replace('@hascourseDetail', hascourseDetail)
                    .replace('@jcdgShow', jcdgShow)
                    .replace('@needbook', needbook)
                    .replace('@nocourseDetail', nocourseDetail)
                    .replace('@hasBook',dataItem.hasBook);
            }
        }
        return html;
    }

    function schoolInit($dom, _data) {
        var wrapTemplate = $('#tpl-school-list').html();
        var rowTemplate = $('#tpl-school-list-row').html();

        var html = buildSchoolCourseListHtml(rowTemplate, _data);
        if (html != null && html.length > 0) {
            wrapTemplate = wrapTemplate.replace('@body', html)
                .replace('@totalPage', schoolTotalPage)
                .replace("@pageNumber", schoolPageNumber + 1);
            $dom.html(wrapTemplate);
            // 绑定翻页事件
            $("#schoolUp").on("click", function(e) {
                pagingCourse('up', 'school');
            });
            $("#schoolDown").on("click", function(e) {
                pagingCourse('down', 'school');
            });
            // 绑定排序事件
            $("#schoolSort").on("click", function(event) {
                expertModeSorting(event, 'school');
            });
        } else {
            wrapTemplate = wrapTemplate.replace('@body', noDataHtml)
                .replace('@totalPage', 0)
                .replace("@pageNumber", 1);
            $dom.html(wrapTemplate);
        }
    }

    function schoolReload($dom, _data) {
        var rowTemplate = $('#tpl-school-list-row').html();
        var html = buildSchoolCourseListHtml(rowTemplate, _data);
        if (html != null && html != '') {
            $dom.html(html);
        } else {
            $dom.html(noDataHtml);
        }
        // 更新页面的页码
        $('#schoolTotalPage').html(schoolTotalPage);
        $('#schoolPageNumber').html(schoolPageNumber + 1);
    }

    /**
     * 创建全校课程列表
     */
    function buildSchoolCourseListHtml(template, _data) {
        var html = '';
        if (_data != null && _data.length > 0) {
            for (var i = 0, length = _data.length; i < length; i++) {
                var dataItem = _data[i];
                var courseNumber = dataItem.courseNumber;
                var courseName = dataItem.courseName;
                courseName = courseName == null ? '-' : courseName;
                var courseIndex = dataItem.courseIndex;
                var departmentName = dataItem.departmentName;
                departmentName = departmentName == null ? '-' : departmentName;
                var courseNatureName = dataItem.courseNatureName;
                courseNatureName = courseNatureName == null ? '-' : courseNatureName;
                var courseTypeName = dataItem.courseTypeName;
                courseTypeName = courseTypeName == null ? '-' : courseTypeName;
                var credit = dataItem.credit;
                var hours = dataItem.hours;
                var teacherName = '';
                var teacherNameTpl = dataItem.teacherName;
                if(!teacherNameTpl){
                	teacherName = '-';
                }else{
                	$.each(teacherNameTpl.split(','), function(index, obj){
                		if(obj){
                			teacherName += obj.split('|')[0] + ',';
                		}
                	});
                	teacherName = teacherName.substring(0, teacherName.length - 1);
                }
                var sportName = dataItem.sportName;
                var engpName = dataItem.engpName;
                if (sportName != null) {
                    courseNumber += '[' + sportName + ']';
                }else if(engpName){
                    courseNumber += '[' + engpName + ']';
                }
                var courseFlag = dataItem.courseFlag;
                var courseFlagDisplay = 'cv-hide';
                if(courseFlag){
                	courseFlagDisplay = 'cv-show';
                }else{
                	courseFlag = '';
                }
                html += template.replace('@courseNumber', courseNumber)
                    .replace('@courseName', courseName)
                    .replace('@courseIndex', courseIndex)
                    .replace('@courseFlagDisplay', courseFlagDisplay)
                    .replace('@courseFlag', courseFlag)
                    .replace('@departmentName', departmentName)
                    .replace('@courseNatureName', courseNatureName)
                    .replace('@courseTypeName', courseTypeName)
                    .replace('@credit', credit)
                    .replace('@hours', hours)
                    .replace('@teacherName', teacherName)
                    .replace('@index', i);
            }            
        }
        return html;
    }
})(window.CVList = window.CVList || {});

/**
 * 所属方案
 */
(function(_syfa) {
	
	_syfa.init = function(courseNum) {
        init(courseNum);
    };
    
    function init(courseNum){
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
    	var param = {
			data:{
				studentCode: studentInfo.code,
				electiveBatchCode: electiveBatch.code,
				courseNumber: courseNum
			},
			pageSize: pageSize,
			pageNumber: "0"
    	};
    	queryFaDetail({querySetting: JSON.stringify(param)}).done(function(resp){
    		var tableTplHtml = $('#tpl-syfa-list').html();
    		var bodyHtml = '';
    		if(resp.code == '1'){
    			$.each(resp.dataList, function(index, obj){
    				obj.campusName = obj.campusName?obj.campusName:'';
    				obj.type = obj.type?obj.type:'';
    				obj.courseNatureName = obj.courseNatureName?obj.courseNatureName:'';
    				obj.departmentName = obj.departmentName?obj.departmentName:'';
    				bodyHtml += '<tr>' +
    								'<td><span title="' + obj.campusName + '级">' + obj.campusName + '级</td>' +
    								'<td><span title="' + obj.type + '">' + obj.type + '</td>' +
    								'<td><span title="' + obj.courseNatureName + '">' + obj.courseNatureName + '</td>' +
    								'<td><span title="' + obj.departmentName + '">' + obj.departmentName + '</td>' +
    							'</tr>';
    			});
    			tableTplHtml = tableTplHtml.replace('@syfabody', bodyHtml);
    			BH_UTILS.bhWindow(tableTplHtml, '课程所属方案',[], {
    				width: 850,
    				height: 500,
    				close: function() {
    					
    				}
    			});
    			unProgramFalistPageNumber = 0;
    			unProgramFalistTotalPage = Math.ceil(resp.totalCount / pageSize);
    			$('#unProgramFalistTotalPage').html(unProgramFalistTotalPage);
    			$('#unProgramFalistPageNumber').html(unProgramFalistPageNumber + 1);
    			//上一页事件
    			$('#unProgramFalistUp').on('click', function(){
    				pageFaList('up', courseNum);
    			});
    			//下一页事件
    			$('#unProgramFalistDown').on('click', function(){
    				pageFaList('down', courseNum);
    			});
    		}else{
    			$.bhTip({
                    content: "查询方案失败",
                    state: 'danger'
                });
    		}
    	});
    }
    
    function pageFaList(type, courseNum){
    	if (unProgramFalistTotalPage > 1) {
            //推荐选课翻页
            if (type == "up" && unProgramFalistPageNumber > 0) {
            	unProgramFalistPageNumber = unProgramFalistPageNumber - 1;
                falistReload(courseNum);
            } else if (type == "down" && unProgramFalistPageNumber < (unProgramFalistTotalPage - 1)) {
            	unProgramFalistPageNumber = unProgramFalistPageNumber + 1;
            	falistReload(courseNum);
            }
        }
    }
    
    function falistReload(courseNum){
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
    	var param = {
			data:{
				studentCode: studentInfo.code,
				electiveBatchCode: electiveBatch.code,
				courseNumber: courseNum
			},
			pageSize: pageSize,
			pageNumber: unProgramFalistPageNumber
    	};
    	queryFaDetail({querySetting: JSON.stringify(param)}).done(function(resp){
    		var bodyHtml = '';
    		if(resp.code == '1'){
    			$.each(resp.dataList, function(index, obj){
    				obj.campusName = obj.campusName?obj.campusName:'';
    				obj.type = obj.type?obj.type:'';
    				obj.courseNatureName = obj.courseNatureName?obj.courseNatureName:'';
    				obj.departmentName = obj.departmentName?obj.departmentName:'';
    				bodyHtml += '<tr>' +
    								'<td><span title="' + obj.campusName + '级">' + obj.campusName + '级</td>' +
    								'<td><span title="' + obj.type + '">' + obj.type + '</td>' +
    								'<td><span title="' + obj.courseNatureName + '">' + obj.courseNatureName + '</td>' +
    								'<td><span title="' + obj.departmentName + '">' + obj.departmentName + '</td>' +
    							'</tr>';
    			});
    			$('.syfa-table tbody').html(bodyHtml);
    			unProgramFalistTotalPage = Math.ceil(resp.totalCount / pageSize);
    			$('#unProgramFalistTotalPage').html(unProgramFalistTotalPage);
    			$('#unProgramFalistPageNumber').html(unProgramFalistPageNumber + 1);
    		}else{
    			$.bhTip({
                    content: "查询方案失败",
                    state: 'danger'
                });
    		}
    	});
    }
    
})(window.CVSyfaList = window.CVSyfaList || {});

/**
 * 课表
 */
;
(function(_table) {
    /**
     * 课表初始化
     * @param $dom {jQuery} 要初始化的节点
     * @param _data {object}
     * @param _data.1-2 {Array} 上午1-2节课,数组内包含7条数组对象,每个对象是对应的课程
     * @param _data.1-2.title {string} 课程标题
     * @param _data.1-2.time {string} 课程时间
     * @param _data.1-2.selected {boolean} 课程是否已经选中
     * @param _data.3-4 {Array} 上午3-4节课
     * @param _data.5-6 {Array} 中午5-6节课
     * @param _data.7-8 {Array} 下午7-8节课
     * @param _data.9-10 {Array} 下午9-10节课
     * @param _data.11-12 {Array} 晚上11-12节课
     */
    _table.init = function($dom, _data) {
        init($dom, _data);
    };

    function init($dom, _data) {
        var row1_2 = _data['1-2'];
        var row3_4 = _data['3-4'];
        var row5_6 = _data['5-6'];
        var row7_8 = _data['7-8'];
        var row9_10 = _data['9-10'];
        var row11_12 = _data['11-12'];

        var tableTemplate = $('#tpl-course-table').html();

        //拼接没行内人的html
        var contentHtml = '';
        contentHtml += getRowHtml(row1_2);
        contentHtml += getRowHtml(row3_4);
        contentHtml += getRowHtml(row5_6);
        contentHtml += getRowHtml(row7_8);
        contentHtml += getRowHtml(row9_10);
        contentHtml += getRowHtml(row11_12);

        var tableHtml = tableTemplate.replace('@content', contentHtml);
        $dom.html(tableHtml);

        //重置左侧与内容高保持一致
        resetTableHeight($dom);
    }

    /**
     * 重置左侧与内容高保持一致
     * @param $dom
     */
    function resetTableHeight($dom) {
        var rowsHeight = [];
        $dom.find('.cv-body').find('.cv-row').each(function(index, item) {
            var rowHeight = $(this).outerHeight();
            rowsHeight.push(rowHeight);
        });

        $dom.find('section.cv-left').find('.cv-block-item').each(function(index, item) {
            var $item = $(this);
            var $left = $item.children('.cv-left');
            var $right = $item.children('.cv-right');
            var $lessons = $right.children('.cv-lesson-block-item');
            switch (index) {
                case 0:
                    $left.css('height', (rowsHeight[0] + rowsHeight[1]) + 'px');
                    $right.css('height', (rowsHeight[0] + rowsHeight[1]) + 'px');
                    $($lessons[0]).css('height', (rowsHeight[0]) + 'px');
                    $($lessons[1]).css('height', (rowsHeight[1]) + 'px');
                    break;
                case 1:
                    $left.css('height', (rowsHeight[3]) + 'px');
                    $right.css('height', (rowsHeight[3]) + 'px');
                    $lessons.css('height', (rowsHeight[3]) + 'px');
                    break;
                case 2:
                    $left.css('height', (rowsHeight[4] + rowsHeight[5]) + 'px');
                    $right.css('height', (rowsHeight[4] + rowsHeight[5]) + 'px');
                    $($lessons[0]).css('height', (rowsHeight[4]) + 'px');
                    $($lessons[1]).css('height', (rowsHeight[5]) + 'px');
                    break;
                case 3:
                    $left.css('height', (rowsHeight[6]) + 'px');
                    $right.css('height', (rowsHeight[6]) + 'px');
                    $lessons.css('height', (rowsHeight[6]) + 'px');
                    break;
                default:
                    break;

            }
        });
    }

    /**
     * 获取每行的html
     * @param _data
     * @returns {string}
     */
    function getRowHtml(_data) {
        var rowTemplate = '<div class="cv-row">@cols</div>';
        var colsHtml = '';

        for (var i = 0, len = _data.length; i < len; i++) {
            colsHtml += getColHtml(_data[i]);
        }
        return rowTemplate.replace('@cols', colsHtml);
    }

    /**
     * 获取行内每列的html,包含课程html
     * @param _data
     * @returns {string}
     */
    function getColHtml(_data) {
        var colTemplate = '<div class="cv-col @class" onclick="">@cards</div>';
        var _class = '';
        var cardHtml = '';
        var hasSelected = false;

        var len = _data.length;
        if (len > 0) {
            for (var i = 0; i < len; i++) {
                var item = _data[i];
                var selected = item.selected;
                //拼接该列内的课程
                cardHtml += CVCourseCardSingle.getHtml(item);

                if (selected) {
                    hasSelected = true;
                }
            }

            //设置该列内课程的是单个还是多个
            if (len === 1) {
                _class = 'cv-single';
            } else {
                _class = 'cv-multiple';
            }

            //当有课程被选中后添加的样式
            if (hasSelected) {
                _class += ' cv-active';
            }
        } else {
            //没有课程的样式
            _class = 'cv-none';
        }

        return colTemplate.replace('@class', _class)
            .replace('@cards', cardHtml);
    }

})(window.CVCourseTable = window.CVCourseTable || {});

/**
 * 对话框
 */
;
(function(_dialog) {
    /**
     * 显示对话框
     * @param _data {object}
     * @param _data.title {string} 课程标题
     */
    _dialog.show = function(_data, e, type) {
        showDialog(_data, e, type);
    };

    _dialog.showLogOut = function(_data, e) {
        showLogOut(_data, e);
    };

    _dialog.showSuccess = function(_data) {
        showSuccess(_data);
    };

    _dialog.showDanger = function(_data) {
        showDanger(_data);
    };

    _dialog.showPublicBook = function(e, type) {
    	showPublicBook(e, type);
    };

    _dialog.showPublicBookWidthTest = function(tcId, capacitySuffix, type) {
    	showPublicBookWidthTest(tcId, capacitySuffix, type);
    };
    
    _dialog.showWarning = function(_data) {
    	showWarning(_data);
    };

    /**
     * 移除弹框
     */
    _dialog.remove = function() {
        removeDialog();
    };
    
    /**
     * 阻止页面滚动
     */
    _dialog.unScroll = function() {
    	unScroll();
    };
    
    /**
     * 恢复页面滚动
     */
    _dialog.restoreScroll = function() {
    	restoreScroll();
    };
    
    

    function showSuccess(_data) {
        var template =
            '<div id="cvDialog" class="cv-dialog cv-success">' +
            '<div class="cv-dialog-modal"></div>' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag">确认</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);
        unScroll();
        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this));
        });
    }

    function showDanger(_data) {
        var template =
            '<div id="cvDialog" class="cv-dialog cv-danger">' +
            '<div class="cv-dialog-modal"></div>' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag">确认</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);
        var $dialog = $(html);
        $('body').append($dialog);
        unScroll();
        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this));
        });
    }

    function showWarning(_data) {
        var template =
            '<div id="cvDialog" class="cv-dialog cv-warning">' +
            '<div class="cv-dialog-modal"></div>' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag" type="sure" data-type="sure">确认</div>' +
            '<div class="cv-cancel cvBtnFlag" type="cancel" data-type="cancel">取消</div>' +
            '</div>' +
            '</div>' +
            '</div>';
        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);
        unScroll();
        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
        	var $btn = $(this);
            var dataType = $btn.attr('type');
            cancelHandle();
            if (dataType === 'sure' && _data.callback) {
            	_data.callback();
            }
        });
    }

    /**
     * 显示对话框
     * @param _data {object}
     * @param _data.title {string} 课程标题
     */
    function showDialog(_data, e, type) {
        var template =
            '<div id="cvDialog" class="cv-dialog @type">' +
            '<div class="cv-dialog-modal"></div>' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cvBtnFlag" type="sure">确认</div>' +
            '<div class="cv-cancel cvBtnFlag" type="cancel">取消</div>' +
            '</div>' +
            '</div>' +
            '</div>';

        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);
        unScroll();
        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            $('#cvDialog').remove();
            btnHandle($(this), e, type);
        });
    }

    /**
     * 显示对话框
     */
    function showPublicBook(e, type) {
    	var template =
    		'<div id="cvDialog" class="cv-dialog public-book">' +
    		'<div class="cv-dialog-modal"></div>' +
    		'<div>' +
    		'<div class="cv-body">' +
            '<div>确认选择？</div>' +
//    		'<div class="bh-switch"><label class="bh-switch-label">是否订购教材</label><input type="checkbox" checked="checked" id="sfbook_' + $(e.currentTarget).attr('tcId') + '"><label class="bh-switch-helper"></label></div>' +
    		'</div>' +
    		'<div class="cv-foot">' +
    		'<div class="cv-sure cvBtnFlag" type="sure">确认</div>' +
    		'<div class="cv-cancel cvBtnFlag" type="cancel">取消</div>' +
    		'</div>' +
    		'</div>' +
    		'</div>';
    	
    	var $dialog = $(template);
    	$('body').append($dialog);
    	unScroll();
    	//点击页脚按钮的事件
    	$dialog.on('click', '.cvBtnFlag', function() {
    		btnHandle($(this), e, type);
    		$('#cvDialog').remove();
    	});
    }

    /**
     * 显示对话框
     */
    function showPublicBookWidthTest(tcId, capacitySuffix, type) {
    	var template =
    		'<div id="cvDialog" class="cv-dialog public-book">' +
    		'<div class="cv-dialog-modal"></div>' +
    		'<div>' +
    		'<div class="cv-body">' +
    		'<div>确认选择？</div>' +
//    		'<div class="bh-switch"><label class="bh-switch-label">是否订购教材</label><input type="checkbox" checked="checked" id="sfbook_' + tcId + '"><label class="bh-switch-helper"></label></div>' +
    		'</div>' +
    		'<div class="cv-foot">' +
    		'<div class="cv-sure cvBtnFlag" type="sure">确认</div>' +
    		'<div class="cv-cancel cvBtnFlag" type="cancel">取消</div>' +
    		'</div>' +
    		'</div>' +
    		'</div>';
    	
    	var $dialog = $(template);
    	$('body').append($dialog);
    	unScroll();
    	//点击页脚按钮的事件
    	$dialog.on('click', '.cvBtnFlag', function() {
    		var type = $(this).attr('type');
            if (type === 'sure') {
            	var needBook = '';
                if($('#sfbook_' + tcId).length > 0){
                	if($('#sfbook_' + tcId).prop('checked')){
                		needBook = '1';
                	}else{
                		needBook = '0';
                	}
                }
                CVTestCourse.initCourse(tcId, capacitySuffix, needBook);
            }
            removeDialog();
    	});
    }

    function showLogOut(_data, e) {
        var template =
            '<div id="cvDialog" class="cv-dialog @type">' +
            '<div class="cv-dialog-modal"></div>' +
            '<div>' +
            '<div class="cv-body">' +
            '<img class="cv-mb-16" src="public/images/curriculaVariable/dialog-icon.png">' +
            '<h2 class="cv-mb-8">@title</h2>' +
            '<div>@content</div>' +
            '</div>' +
            '<div class="cv-foot">' +
            '<div class="cv-sure cv-logout" type="sure" data-type="sure">确认</div>' +
            '<div class="cv-cancel cv-logout" type="cancel" data-type="cancel">取消</div>' +
            '</div>' +
            '</div>' +
            '</div>';

        var title = _data.title;
        var content = _data.content;
        var html = template.replace('@title', title).replace('@content', content);

        var $dialog = $(html);
        $('body').append($dialog);
        unScroll();
        $dialog.on('click', '.cv-logout', function() {
            var $btn = $(this);
            var dataType = $btn.attr('type');
            if (dataType === 'sure') {
                logOut();
            } else {
                cancelHandle();
            }
        });
    }
    
    /**
     * 点击页脚按钮的事件
     * @param $btn 被点击的按钮
     */
    function btnHandle($btn, e, addType) {
        var type = $btn.attr('type');
        if (type === 'sure') {
            sureHandle(e, addType);
        } else {
            cancelHandle(e);
        }
    }

    /**
     * 取消
     */
    function cancelHandle(e) {
        removeDialog(e);
    }

    /**
     * 确认
     */
    function sureHandle(e, type) {
        if (type == 'addPublic') {
            // 教学班id
            var tcId = $(e.currentTarget).attr('tcId');
            var capacitySuffix = $(e.currentTarget).attr('capacitySuffix');
            var addParam = buildAddVolunteerParam(tcId);
            addVolunteer(addParam).done(function(resp) {
                var code = resp.code;
                removeDialog();
                if (code != null && code == '1') {
                    initProcessInterval(function(processResp){
                    	if(processResp.code == '1'){
                    		$.bhTip({
                    			content: '添加选课成功',
                    			state: 'success'
                    		});
                    		window.cardOperateBtn.hide();
                    		var $setting = window.cardOperateBtn.closest('.cv-setting-col');
                    		$setting.addClass('cv-selected');
                    		$setting.find('.cv-tag').html('已选');
                    		flushTeachingClassCapacity(tcId, capacitySuffix);
                        	// 查询已选课程数量
                        	querySelectCourseNum();
                    	}else if(processResp.code == '-1'){
                    		$.bhTip({
                    			content: processResp.msg,
                    			state: 'danger'
                    		});
                    	}
                    });
                } else if (code == '302') {
                    sessionStorage.removeItem('token');
                    sessionStorage.removeItem('studentInfo');
                    window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
                } else {
                    var failObj = new Object();
                    failObj.title = '失败';
                    failObj.content = resp.msg;
                    CVDialog.showDanger(failObj);
                }

            });
        } else if (type == 'delSelectCourse') {
            removeDialog();
            deleteVolunteer(e);
        }
    }

    function deleteVolunteer(e) {
    	var $this = $(e.currentTarget);
        var teachingClassID = $this.attr('tcId');
        var capacitySuffix = $this.attr('capacitySuffix');
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code; // 学号
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code; // 选课批次
        var delData = '{"operationType":"2"' + ',"studentCode":"' + studentCode + '"' + ',"electiveBatchCode":"' + electiveBatchCode + '"' + ',"teachingClassId":"' + teachingClassID + '"' + ',"isMajor":"1"}';
        var delStr = '{"data":' + delData + '}';
        var deleteParam = {
            'deleteParam': delStr
        };

        articleId = $this.closest('article').attr('id');
        txIndex = $this.closest('.cv-row').attr('index');
        cardIndex = $this.closest('.cv-course-card').index();
        deleteVolunteerResult(deleteParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                initProcessInterval(function(processResp){
                	$('#cvDialog .cv-foot .cv-cancel').trigger("click");
                	if(processResp.code == '1'){
                		$.bhTip({
                			content: '删除选课结果成功',
                			state: 'success'
                		});
                		var $card = $this.closest('.cv-course-card');
                		var $row = $this.closest('.cv-row');
                		$row.removeClass('cv-active').attr('ischoose', '0');
                		$card.attr('ischoose', '0');
                		$card.find('.cv-select-flag').addClass('cv-block-hide').removeClass('cv-one').html('');
                		$card.find('.cv-delete-volunteer').addClass('cv-block-hide');
                		flushTeachingClassCapacity(teachingClassID, capacitySuffix);
                		// 查询已选课程数量
                		querySelectCourseNum();
                	}else if(processResp.code == '-1'){
                		$.bhTip({
                			content: processResp.msg,
                			state: 'danger'
                		});
                	}
                });
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                var failObj = new Object();
                failObj.title = '失败';
                failObj.content = resp.msg;
                CVDialog.showDanger(failObj);
            }
        });
    }

    function logOut() {
        var stundentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));//学生信息
        var studentNumber = stundentInfo.code;// 学号
        var logOutParam = {'studentNumber' : studentNumber};
        studentLogOut(logOutParam).done(function(resp){            
            autoLogOut();
            sessionStorage.removeItem('token');
            sessionStorage.removeItem('studentInfo');
            sessionStorage.removeItem('currentBatch');
            if (loginType == 'cas') {
            	window.location.href = casUrlOut;
        	}else{
        		window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
        	}
        });
    }
    
    //阻止页面滚动
    function unScroll() {
    	var top = $(document).scrollTop();
        $(document).on('scroll.unable',function (e) {
            $(document).scrollTop(top);
        });
    }
    //恢复滚动
    function restoreScroll(){
    	$(document).unbind("scroll");
    }

    /**
     * 移除弹框
     */
    function removeDialog() {
        $('#cvDialog').remove();
        restoreScroll();
    }
})(window.CVDialog = window.CVDialog || {});
/**
 * 下拉框
 */
;
(function(_dropdown) {
    //点击下拉框外的地方,移除下拉框
    $('body').on('click', function(e) {
        var $target = $(e.target || e.srcElement);
        if ($target.closest('.cv-dropdown-dialog').length === 0 && $target.closest('.cv-select').length === 0) {
            removeDialog();
        }
    });

    /**
     * 下拉框内容初始化
     */
    _dropdown.init = function($item, _data, type, slideType) {
        if (type == 'volunteer') {
            initVolunteerDropdown($item, _data);
        } else if (type == 'campus') {
            initCampus($item, _data, slideType);
        }
    };

    /**
     * 移除下拉框内容
     */
    _dropdown.remove = function() {
        removeDialog();
    };

    function removeDialog() {
        $('body').find('.cv-dropdown-dialog').remove();
    }

    /**
     * 初始化志愿下拉框
     */
    function initVolunteerDropdown($item, _data) {
        var width = $item.outerWidth();
        var height = $item.outerHeight();
        var offset = $item.offset();
        var top = offset.top;
        var left = offset.left;
        var bottom = top + height + 4;
        var template =
            '<div class="cv-dropdown-dialog" style="top:' + bottom + 'px;left:' + left + 'px;width: ' + width + 'px;">';
        for (var i = 0, length = _data.length; i < length; i++) {
            var volunteer = _data[i];
            template += '<div class="volunteerIndex" grade=' + volunteer.grade + '>' + volunteer.name + '</div>';
        }
        template += '</div>';
        var $body = $('body');
        removeDialog();
        $body.append(template);
        // 绑定选课志愿下拉点击触发事件
        $('.volunteerIndex').on('click', function(e) {
            var grade = $(e.currentTarget).attr('grade');
            var text = $(e.currentTarget).text();
            removeDialog();
            $('.cv-flag').attr('grade', grade);
            $('.cv-flag').html(text);
        });
    }

    /**
     * 初始化校区下拉框
     */
    function initCampus($item, _data, slideType) {
        var width = $item.outerWidth();
        var height = $item.outerHeight();
        var offset = $item.offset();
        var top = offset.top;
        var left = offset.left;
        var bottom = top + height + 4;
        var windowHeight = document.documentElement.clientHeight || document.body.clientHeight;
        var maxHeight = 0;
        if(slideType == 'slide'){
        	maxHeight = windowHeight - top - height + $(window).scrollTop() - 10;
        }else{
        	maxHeight = windowHeight - bottom - 10;
        }
        var template =
            '<div class="cv-dropdown-dialog" style="overflow-y: auto;top:' + bottom + 'px;left:' + left + 'px;width: ' + width + 'px;max-height: ' + maxHeight + 'px;">';
        var campus = null;
        for (var i = 0, length = _data.length; i < length; i++) {
            campus = _data[i];
            template += '<div class="campusList" code=' + campus.code + '>' + campus.name + '</div>';
        }
        template += '</div>';
        var $body = $('body');
        removeDialog();
        $body.append(template);
        // 绑定校区下拉点击触发事件
        $('.campusList').on('click', function(e) {
            removeDialog();
            // 当前校区
            var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
            // 新选择的校区
            var code = $(e.currentTarget).attr('code');
            var name = $(e.currentTarget).text();
            // 切换不同的校区（1：更新当前校区 2：更新页面列表数据）
            if (currentCampus != null && currentCampus.code != code) {
                $('#changeCampus').attr("code", code);
                $('#changeCampus').html("切换校区 : " + name);
                var currentCampus = {
                    'code': code,
                    'name': name
                };
                sessionStorage.setItem('currentCampus', JSON.stringify(currentCampus));
                reloadTable('0');
            }
        });
    }

})(window.CVDropdownDialog = window.CVDropdownDialog || {});

/**
 * 页头的相关事件方法
 */
;
(function(_head) {
    /**
     * 初始化
     */
    _head.init = function() {
        //事件监听
        eventsListen();
    };

    /**
     * 事件监听
     */
    function eventsListen() {
        //tab栏点击
        $('#cvPageHeadTab').on('click', 'a', function() {
            var disabledAttr = $(this).attr('disabled');
            if (disabledAttr == null || disabledAttr != 'disabled') {
                pageHeadTabChange($(this));
            }
        });
    }

    /**
     * 切换tab对应的模块
     * @param $a 被点击的a标签对象
     */
    function pageHeadTabChange($a) {
        var id = $a.attr('href');
        var $li = $a.closest('li');
        var teachingClassType = $a.attr('teachingClassType');
        // 已打开的tab，不处理
        if ($li.hasClass('cv-active')) {
            return;
        }
        // 删除隐藏属性
        $('.main').children('article').addClass('cv-block-hide');
        $(id).removeClass('cv-block-hide');

        // 更新缓存中教学班类型
        sessionStorage.setItem("teachingClassType", teachingClassType);

        // 初始化课程列表
        if (id == '#cvRecommendCourse') {
            // 推荐课程
            recommendPageNumber = 0;
            recommendOrder = '';
            CVRecommendCourse.listInit();
        } else if (id == '#cvProgramCourse') {
            // 计划内课程
            programPageNumber = 0;
            programOrder = '';
            CVProgramCourse.listInit();
        } else if (id == '#cvUnProgramCourse') {
            // 计划外课程
            unProgramPageNumber = 0;
            unProgramOrder = '';
            CVUnProgramCourse.listInit();
        } else if (id == '#cvPublicCourse') {
            // 公选课
            publicPageNumber = 0;
            publicOrder = '';
            CVPublicCourse.listInit();
        } else if (id == '#cvRetakeCourse') {
            // 重修
            retakePageNumber = 0;
            retakeOrder = '';
            CVRetakeCourse.listInit();
        } else if (id == '#cvSportCourse') {
            // 体育课
            sportPageNumber = 0;
            sportOrder = '';
            CVSportCourse.listInit();
        } else if (id == '#cvMinorCourse') {
            // 辅修课
            minorPageNumber = 0;
            minorOrder = '';
            CVMinorCourse.listInit();
        } else if (id == '#cvSchoolCourse') {
            // 全校课程
            schoolPageNumber = 0;
            schoolOrder = '';
            CVSchoolCourse.listInit();
        }
    }
})(window.CVPageHead = window.CVPageHead || {});

/**
 * 实验课程
 */
;
(function(_test) {

    _test.initCourse = function(jxbid, capacitySuffix, needBook) {
        openTestCourseWindow(jxbid, capacitySuffix, needBook);
    };
    
    //获取勾选的教材
    function getSelectJcxx(){
    	var seljcxx = '';
    	var wdgyy = [];
    	$("select[name='select_jc']").each(function(index, jcobj){
    		wdgyy.push($(jcobj).val());
		});
	    $("select[name='testCourse_radio_jc']").each(function(index, jcobj){
			var jcbh = $(jcobj).attr('jcbh');
			var sel = $(jcobj).val()=="1";
			seljcxx += ',' + jcbh + (sel ? '' : ('-' + wdgyy[index]));
		});
		return seljcxx.substr(1);
    }
    
    //拼凑教材列表
    function getJcHtml(jcxx){
    	if(jcxx==null || jcxx.length<1){
    		return '';
    	}
    	var selectJctdyy = '<select name="select_jc" class="bh-form-control jctdyy" disabled="disabled"><option value="***">请选择</option>';
    	$.each(JSON.parse(sessionStorage.getItem('dictionary')).TJCYY,function(index,item){
    		selectJctdyy += '<option '+' value="'+item.code+'">'+item.name+'</option>';
    	});
    	selectJctdyy+="</select>";
    	//var selectCheckBox = '<input name="testCourse_radio_jc" jcbh=@jcbh checked type="checkbox">' + '</input>';
    	var selectCheckBox = '<select name="testCourse_radio_jc" onchange="changeJcWdgyy(this)" class="bh-form-control" style="width:50px" jcbh=@jcbh><option value="1">是</option><option value="0">否</option></select>';
    	var tbodyHtml = '';
    	$.each(jcxx,function(index,obj1){
    		var obj = JSON.parse(obj1);
    		var rowTplHtml = $('#tpl-test-course-table-row-jc').html();
            rowTplHtml = rowTplHtml.replace('@checkboxHtml', selectCheckBox)
                .replace('@wdgyy', selectJctdyy)
                .replace('@isbn', obj.ISBN||'')
                .replace('@mc', obj.SM||'')
                .replace('@zzz', obj['ZZZ']||'')
                .replace('@dj', obj.JD||'')
                .replace('@jcbh', obj.JCBH);
            tbodyHtml += rowTplHtml;
    	});
    	if(tbodyHtml){
		    var tableTplHtml = $('#tpl-test-course-table-jc').html();
		    tableTplHtml = tableTplHtml.replace('@tbody', tbodyHtml);
		    return tableTplHtml;
    	}
    	return "";
    }
    // 打开实验选课窗口
    function openTestCourseWindow(jxbid, capacitySuffix, needBook) {
        // 选课批次
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo')); //学生信息
        var studentCode = studentInfo.code; // 学号
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code;// 选课批次
        var isMajor = '1'; // 是否主修
        var teachingClassType = sessionStorage.getItem("teachingClassType"); // 教学班类型
        var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
        var campus = currentCampus.code; // 校区
        var checkCapacity = '0'; // 是否检查课容量
        var checkConflict = '0'; // 是否检查冲突
        var jcxxHtml = ''; //教材的信息
        
        var queryParam = {
            jxbid : jxbid,
            electiveBatchCode : electiveBatchCode,
            studentCode : studentCode,
            isMajor : isMajor,
            teachingClassType : teachingClassType,
            campus : campus,
            checkCapacity : checkCapacity,
            checkConflict : checkConflict
        };
        queryTestCourse(queryParam).done(function(resp){
            var code = resp.code;
            code = '1';
            if (code != null && code == '1') {
            	//获取教材信息
            	jcxxHtml = getJcHtml(resp.map);
            	
                var dataList = resp.dataList;
                if (dataList != null && dataList.length > 0) {
                    var course = dataList[0];
                    var courseName = course.courseName;
                    var courseNumber = course.courseNumber;
                    var theoryClassInfo = courseNumber + ' - ' + courseName;
                    var theoryClassTeachingPlace = '理论课时间地点:' + (course.wid ? course.wid : '-') + '<br>该教学班有' + window.CVParams.sykbs + ',请选择';
                    
                    // 创建实验教学班列表
                    var tbodyHtml = '';
                    var tcList = course.tcList;
                    var tc = null;
                    var numberOfSelected = null;
                    var classCapacity = null;
                    var cannotSelectReason = '';
                    var radioHtml = '';
                    for (var i = 0, length = tcList.length; i < length; i++) {
                        tc = tcList[i];
                        numberOfSelected = tc.numberOfSelected;
                        numberOfSelected == null ? 0 : numberOfSelected;
                        classCapacity = tc.classCapacity;
                        classCapacity == null ? 0 : classCapacity;
                        cannotSelectReason = '';
                        if(tc.isConflict == '1'){
                        	cannotSelectReason += '时间冲突';
                        }
                        if(tc.isLimitKind == '1'){
                        	cannotSelectReason += '选课限制';
                        }
                        if(tc.isFull == '1' || tc.extInfo == '1'){
                        	cannotSelectReason += '课容量不足';
                        }
                        if(cannotSelectReason.length == 0){
                        	radioHtml = '<input type="radio" name="testCourse_radio" value="' + tc.teachingClassID + '">';
                        }else{
                        	radioHtml = '';
                        }
                        var rowTplHtml = $('#tpl-test-course-table-row').html();
                        rowTplHtml = rowTplHtml.replace('@courseIndex', tc.courseIndex)
                            .replace('@teacher', tc.teacherName == null ? '未安排教师' : tc.teacherName)
                            .replace('@teachingPlace', tc.teachingPlace == null ? '未安排时间地点' : tc.teachingPlace)
                            .replace('@extInfo', tc.extInfo == null ? '' : tc.extInfo)
                            .replace('@remainingCapacity', numberOfSelected + '/' + classCapacity)
                            .replace('@radioHtml', radioHtml)
                            .replace('@cannotSelectReason', cannotSelectReason)
                            .replace('@numberOfSelected', numberOfSelected);
                        tbodyHtml += rowTplHtml;
                    }
                    var tableTplHtml = $('#tpl-test-course-table').html();
                    tableTplHtml = tableTplHtml.replace('@tbody', tbodyHtml).replace('@theoryClassInfo', theoryClassInfo).replace('@theoryClassTeachingPlace',theoryClassTeachingPlace).replace('@jcxxHtml', jcxxHtml);
                    var $dom = BH_UTILS.bhWindow(tableTplHtml, '',[], {
                        width: 850,
                        maxHeight: 1000,
                        maxWidth: 1200,
                        close: function() {
                        	
                        }
                    });
                    $('#testCourse_choice_btn_jc').hide();
                    $('#testCourse_choice_title_jc').hide();
                    //
                    $('#testCourse_choice_btn').on('click', function(event) {
                        var teachingClassId = $("input[name='testCourse_radio']:checked").val();
                        if(!teachingClassId){
                        	$.bhTip({
                                content: '未选择' + window.CVParams.sykbs,
                                state: 'warning'
                            });
                        	return;
                        }
                        //是否有教材
                        var seljcxx = '';
                        if(jcxxHtml){
                        	seljcxx = getSelectJcxx();
                    		if(seljcxx.indexOf('***')>0){
                    			$.bhTip({
                                    content: '请订购教材，或者选择不订购教材原因',
                                    state: 'warning'
                                });
                    			return;
                    		}
                        }
                        choiceTestCourse(jxbid, teachingClassId, $dom, seljcxx);
                    });
                }else{
                	var tableTplHtml = jcxxHtml.replace('@theoryClassInfo', '是否订购教材:');
                	var $dom = BH_UTILS.bhWindow(tableTplHtml, '',[], {
                        width: 850,
                        maxHeight: 1000,
                        maxWidth: 1200,
                        close: function() {
                        	
                        }
                    });
                	$('#testCourse_choice_btn_jc').on('click', function(event) {
                		var seljcxx = getSelectJcxx();
                		if(seljcxx.indexOf('***')>0){
                			$.bhTip({
                                content: '请订购教材，或者选择不订购教材原因',
                                state: 'warning'
                            });
                		}else{
                			choiceTestCourse(jxbid, '', $dom, seljcxx);
                		}
                    });
                }    
            }
        });       
    }

    /**
     * 选择实验课程
     */
    function choiceTestCourse(tcId, testTcid, $dom, needBook) {
        var addParam = buildAddVolunteerParam(tcId, testTcid, needBook);
        addVolunteer(addParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                initProcessInterval(function(processResp){
                	if(processResp.code == '1'){
                		$.bhTip({
                			content: '添加选课成功',
                			state: 'success'
                		});
                		var teachingClassType = sessionStorage.getItem("teachingClassType"); // 教学班类型
                		var capacitySuffix = window.cardOperateBtn.attr('capacitySuffix');
                    	if(teachingClassType == 'XGXK'){
                    		window.cardOperateBtn.hide();
                    		var $setting = window.cardOperateBtn.closest('.cv-setting-col');
                    		$setting.addClass('cv-selected');
                    		$setting.find('.cv-tag').html('已选');
                    	}else{
                    		var $card = window.cardOperateBtn.closest('.cv-course-card');
                    		var $row = window.cardOperateBtn.closest('.cv-row');
                    		$row.addClass('cv-active').attr('ischoose', '1');
                    		$card.attr('ischoose', '1');
                    		$card.find('.cv-select-flag').removeClass('cv-block-hide').addClass('cv-one').html('已选');
                    		$card.find('.cv-delete-volunteer').removeClass('cv-block-hide');
                    	}
                    	flushTeachingClassCapacity(tcId, capacitySuffix);
                		window.cardOperateBtn = null;
                        // 查询已选课程数量
                        querySelectCourseNum();
                	}else if(processResp.code == '-1'){
                		$.bhTip({
                			content: processResp.msg,
                			state: 'danger'
                		});
                	}
                	$dom.jqxWindow('close');
                });
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                var failObj = new Object();
                failObj.title = '失败';
                failObj.content = resp.msg;
                CVDialog.showDanger(failObj);
            }
        });
    }

})(window.CVTestCourse = window.CVTestCourse || {});

/**
 * 公选课
 */
;
(function(_public) {
    /**
     * 公选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };
    /**
     * 公选课列表重载
     */
    _public.listReload = function(tcId, capacitySuffix, needAppendFlag) {
        listReload(tcId, capacitySuffix, needAppendFlag);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#publicSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryPublicCourse(queryParam).done(function(resp) {
        	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        	$("#publicCourseTip").html(studentInfo.spCourseDescription);
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算公选课总页数（向上取整）
                publicTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'public',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectPublicCourse'), listMock);
                var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
                if(sysParam.xgxkQueryTitle){
                	changeTskName(sysParam.xgxkQueryTitle);
                }
                if(sysParam.noDisplayJxbInfo == '1'){
                	hidePublicJxbxq();
                }
                if(sysParam.xgxkNotPage == '1'){
                	hidePublicFoot();
                	bindPublicScrollPage();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectPublicCourse').html(resp.msg);
            }
        });
    }

    function listReload(tcId, capacitySuffix, needAppendFlag) {
        // 搜索条件内容
        var content = $('#publicSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryPublicCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算公选课总页数（向上取整）
                publicTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'public',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#publicBody'), listMock, needAppendFlag);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
                if(sysParam.xgxkQueryTitle){
                	changeTskName(sysParam.xgxkQueryTitle);
                }
                if(sysParam.noDisplayJxbInfo == '1'){
                	hidePublicJxbxq();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectPublicCourse').html(resp.msg);
            }
        });
    }
})(window.CVPublicCourse = window.CVPublicCourse || {});

/**
 * 方案内选课
 */
;
(function(_public) {
    /**
     * 方案内选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };

    /**
     * 方案内选课列表重载
     */
    _public.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#programSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案选课总页数（向上取整）
                programTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'program',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectProgramCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectProgramCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        // 搜索条件内容
        var content = $('#programSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案选课总页数（向上取整）
                programTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'program',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#programBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }                
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectProgramCourse').html(resp.msg);
            }
        });
    }

    function openRows() {
        var rows = $('.cv-list.program-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }
})(window.CVProgramCourse = window.CVProgramCourse || {});


/**
 * 辅修选课
 */
;
(function(_minor) {
    /**
     * 辅修选课列表初始化
     */
    _minor.listInit = function() {
        listInit();
    };

    /**
     * 辅修选课列表重载
     */
    _minor.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#minorSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案选课总页数（向上取整）
                minorTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'minor',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectMinorCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectMinorCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        // 搜索条件内容
        var content = $('#minorSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案选课总页数（向上取整）
            	minorTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'minor',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#minorBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectMinorCourse').html(resp.msg);
            }
        });
    }

    function openRows(isOpenRow) {
        var rows = $('.cv-list.minor-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }

})(window.CVMinorCourse = window.CVMinorCourse || {});

/**
 * 方案外选课
 */
;
(function(_public) {
    /**
     * 方案外选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };
    /**
     * 方案外选课列表重载
     */
    _public.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#unProgramSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案外选课总页数（向上取整）
                unProgramTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'unProgram',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectUnProgramCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectUnProgramCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        // 搜索条件内容
        var content = $('#unProgramSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算方案外选课总页数（向上取整）
                unProgramTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'unProgram',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#unProgramBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }                            
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectUnProgramCourse').html(resp.msg);
            }
        });
    }

    function openRows() {
        var rows = $('.cv-list.unprogram-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }

})(window.CVUnProgramCourse = window.CVUnProgramCourse || {});

/**
 * 推荐选课
 */
;
(function(_public) {
    /**
     * 推荐选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };
    /**
     * 推荐选课列表重载
     */
    _public.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#recommendSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryRecommendedCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算推荐选课总页数（向上取整）
                recommendTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'recommend',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectRecommendCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectRecommendCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        // 搜索条件内容
        var content = $('#recommendSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryRecommendedCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算推荐选课总页数（向上取整）
                recommendTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'recommend',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#recommendBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectRecommendCourse').html(resp.msg);
            }
        });
    }

    function openRows() {
        var rows = $('.cv-list.recommend-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }

})(window.CVRecommendCourse = window.CVRecommendCourse || {});

/**
 * 全校课程
 */
;
(function(_school) {

    /**
     * 列表初始化
     */
    _school.listInit = function() {
        listInit();
    };

    /**
     * 列表重载
     */
    _school.listReload = function(isOpenRow) {
        listReload(isOpenRow);
    };

    function listInit() {
        var content = $('#schoolSearch').val();
        var queryParam = buildQueryTCParam(content);
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var electiveBatch = studentInfo.electiveBatch;
        var electiveBatchCode = electiveBatch.code;
        queryParam.electiveBatchCode = electiveBatchCode;
        queryCourseData(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算公选课总页数（向上取整）
                schoolTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'school',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectSchoolCourse'), listMock);

                $(".row-school-link").bind("click",function(event){
                    openCourseViewWindow(event, dataList);
                });               
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectSchoolCourse').html(resp.msg);
            }
        });
    }

    function listReload() {
        // 搜索条件内容        
        var content = $('#schoolSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryCourseData(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算全校课程总页数（向上取整）
                schoolTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'school',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#schoolBody'), listMock);

                $(".row-school-link").unbind();
                $(".row-school-link").bind("click",function(event){
                    openCourseViewWindow(event, dataList);
                }); 
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectSchoolCourse').html(resp.msg);
            }
        });
    }

    function openCourseViewWindow(event, dataList) {
        var index = $(event.currentTarget).find('.row-school-index').attr('index');
        var course = dataList[index];
        var html = '';
        if (course != null) {
        	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        	querySfCanChoose(studentInfo.code, course.teachingClassID, studentInfo.electiveBatch.code).done(function(resp) {
        		var chooseBody = '';
        		if(resp.code == '1'){
        			var reasonList = resp.data.reasonList;
        			chooseBody += '<table class="table-all">';
        			for (var j = 0, jLength = reasonList.length; j < jLength; j++) {
        				chooseBody += '<tr><td>' + reasonList[j] + '</td></tr>';
        			}
        			chooseBody += '</table>';
        		}else{
        			chooseBody = '<span>' + resp.msg + '</span>';
        		}
        		var tpl = $('#tpl-schoolcourse-view').html();
        		var courseTitle = course.courseName + '-' + course.courseNumber + '-' + course.courseIndex;
        		var departmentName = course.departmentName;
        		var courseNatureName = course.courseNatureName;
        		var courseTypeName = course.courseTypeName;
        		var credit = course.credit;
        		var hours = course.hours;
        		
        		var teacherName = '';
        		var teacherNameTpl = course.teacherName;
        		if(teacherNameTpl){
        			var customTeachingInfo = sysParam.customTeachingInfo;
        			var teachers = teacherNameTpl.split(',');
        			var tplArr = [];
        			if(customTeachingInfo == "1"){
        				$.each(teachers, function(tcIndex, tcStr){
        					tplArr = tcStr.split('|');
        					if(tplArr.length > 2 && tplArr[2] != null && tplArr[2] != '' && tplArr[2] != undefined){
        						teacherName += '<a class="jsSimple" data-jsh="'+ tplArr[1] + '" href="javascript:void(0)">' + tplArr[0] + '</a> <a class="url" href="' + tplArr[2] + '" target="_blank">[教师主页]</a>';
        					}else{
        						teacherName += '<a class="jsSimple" data-jsh="'+ tplArr[1] + '" href="javascript:void(0)">' + tplArr[0] + '</a>';
        					}
        				});
        			}else{
        				$.each(teachers, function(tcIndex, tcStr){
        					tplArr = tcStr.split('|');
        					if(tplArr[2] != null && tplArr[2] != '' && tplArr[2] != undefined){
        						teacherName += '<a href="' + tplArr[2] + '" target="_blank">' + tplArr[0] + '</a>';
        					}else{
        						teacherName += '<a target="_blank">' + tplArr[0] + '</a>';
        					}
        					
        				});
        			}
        		}
        		
        		var teachingPlace = course.teachingPlace;
        		var campusName = course.campusName;
        		
        		// 面向班级
        		var schoolClass = course.schoolClassMap;
        		var scStr = '';
        		for (sClass in schoolClass) {  
        			scStr = scStr + schoolClass[sClass] + ',';
        		}
        		if (scStr == '') {
        			scStr = '无面向班级';
        		} else {
        			scStr = scStr.substring(0, scStr.length - 1);
        		}
        		// 限制信息
        		var limitKindList = course.limitKindList;
        		var lkStr = '';
        		if (limitKindList != null) {
        			var limitKindObj = {};
        			var limitItemTpl = [];
        			var limitItemObj = {};
        			var yxCodeTpl = ',';
        			var j = 0, jLength = 0;
        			lkStr = '<table class="xzxx-item-table">';
        			for (var i = 0, iLength = limitKindList.length; i < iLength; i++) {
        				limitKindObj = limitKindList[i];
        				if(yxCodeTpl.indexOf(',' + limitKindObj.code + ',') == -1){
        					limitItemTpl = selectXzxx(limitKindObj.code, limitKindList);
        					for (j = 0, jLength = limitItemTpl.length; j < jLength; j++) {
        						limitItemObj = limitItemTpl[j];
        						lkStr += '<tr>';
        						if(j == 0){
        							lkStr += '<td class="xzlx" rowspan="' + jLength + '">' + (limitItemObj.name?limitItemObj.name:'-') + '</td>';
        						};
        						lkStr += '<td class="bjmc">' + (limitItemObj.limitDesc?limitItemObj.limitDesc:'-') + '</td>';
        						if(limitItemObj.limitType == '1'){
        							lkStr += '<td class="xzjg">允许选课</td>';
        						}else{
        							lkStr += '<td class="xzjg">不允许选课</td>';
        						}
        						lkStr += '</tr>';
        					}
        					yxCodeTpl += limitKindObj.code + ',';
        				}
        			}
        			lkStr += '</table>';
        		} else {
        			lkStr = '无限制信息';
        		}
        		
        		var extInfo = course.extInfo;
        		if (extInfo == null || extInfo == '') {
        			extInfo = '无选课说明';
        		}
        		html = tpl.replace('@chooseBody', chooseBody)
        		.replace('@courseTitle', courseTitle)
        		.replace('@departmentName', checkNull(departmentName))
        		.replace('@courseNatureName', checkNull(courseNatureName))
        		.replace('@courseTypeName', checkNull(courseTypeName))
        		.replace('@credit', checkNull(credit))
        		.replace('@hours', checkNull(hours))
        		.replace('@teacherName', teacherName)
        		.replace('@teachingPlace', checkNull(teachingPlace))
        		.replace('@scStr', scStr)
        		.replace('@lkStr', lkStr)
        		.replace('@extInfo', extInfo)
        		.replace('@campusName', checkNull(campusName));
        		
        		BH_UTILS.bhWindow(html, '',[], {
        			width: 600,
        			maxHeight: 500,
        			maxWidth: 600,
        			close:function(){
        				
        			}
        		});
        		
        		$('.schoolcourse-view-table').off('.click', '.jsSimple').on('click', '.jsSimple', function(event){
            		event.stopPropagation();
            		var jsh = $(event.currentTarget).attr('data-jsh');
            		if(!sysParam.customTeachingPage){
            			window.open(BaseUrl + '/sys/xsxkapp/*default/jssimple.do?jsh=' + jsh);
            		}else{
            			window.open(BaseUrl + '/sys/xsxkapp/*default/jssimple1.do?jsh=' + jsh);
            		}
            	});
        	});
        } 
    }
    
    function selectXzxx(code, data){
    	var result = [];
    	for (var i = 0, iLength = data.length; i < iLength; i++) {
    		if(data[i].code == code){
    			result.push(data[i]);
    		}
    	}
    	return result;
    }

    function checkNull(value, replace) {
        if (replace == null) {
            replace = '';
        }
        if (value == null) {
            value = replace;
        }
        return value;
    }

})(window.CVSchoolCourse = window.CVSchoolCourse || {});

/**
 * 重修选课
 */
;
(function(_public) {
    /**
     * 重修选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };
    /**
     * 重修选课列表重载
     */
    _public.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#retakeSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算推荐选课总页数（向上取整）
                retakeTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'retake',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectRetakeCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectRetakeCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        // 搜索条件内容
        var content = $('#retakeSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算推荐选课总页数（向上取整）
                retakeTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'retake',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#retakeBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectRetakeCourse').html(resp.msg);
            }
        });
    }

    function openRows() {
        var rows = $('.cv-list.retake-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }
})(window.CVRetakeCourse = window.CVRetakeCourse || {});

/**
 * 体育选课
 */
;
(function(_public) {
    /**
     * 体育选课列表初始化
     */
    _public.listInit = function() {
        listInit();
    };
    /**
     * 体育选课列表重载
     */
    _public.listReload = function(isOpenRow, tcId, capacitySuffix) {
        listReload(isOpenRow, tcId, capacitySuffix);
    };

    function listInit() {
        // 搜索条件内容
        var content = $('#sportSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算体育选课总页数（向上取整）
                sportTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'sport',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.init($('#cvCanSelectSportCourse'), listMock);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectSportCourse').html(resp.msg);
            }
        });
    }

    function listReload(isOpenRow, tcId, capacitySuffix) {
        var content = $('#sportSearch').val();
        var queryParam = buildQueryTCParam(content);
        queryProgramCourse(queryParam).done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                // 计算体育选课总页数（向上取整）
                sportTotalPage = Math.ceil(resp.totalCount / pageSize);
                var dataList = resp.dataList;
                var listMock = {
                    type: 'sport',
                    data: dataList
                };
                courseDataList = dataList;
                CVList.reload($('#sportBody'), listMock);
                flushTeachingClassCapacity(tcId, capacitySuffix);
                var jxbUnsort = JSON.parse(sessionStorage.getItem('sysParam')).jxbUnsort;
                if (isOpenRow && (jxbUnsort !=1 )) {
                    openRows();
                }
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectSportCourse').html(resp.msg);
            }
        });
    }

    function openRows() {
        var rows = $('.cv-list.sport-list').find('.cv-row');
        for (var i = 0; i < rows.length; i ++) {
            var index = $(rows[i]).attr('index');
            if (selectIndex != null && index == selectIndex) {
                CVList.openRow($(rows[i]));
                break;
            }
        }
    }
})(window.CVSportCourse = window.CVSportCourse || {});

/**
 * 对话框
 */
;
(function(_dialog) {

    //点击弹框的其他区域,关闭弹框
    $('body').on('click', function(e) {
        var $target = $(e.target || e.srcElement);
        if ($target.closest('.cv-popover').length === 0 && $target.closest('.cv-dropdown-dialog').length === 0 && $target.closest('.cv-setting-col').length === 0) {
            removeDialog();
        }
    });

    /**
     * 显示对话框
     * @param $item
     */
    _dialog.show = function($item, _data) {
        showDialog($item, _data);
    };

    /**
     * 移除弹框
     */
    _dialog.remove = function() {
        removeDialog();
    };

    /**
     * 显示对话框
     * @param $item
     */
    function showDialog($item, _data) {
        var dialogStyle = getItemPositionStyle($item);
        var tcId = $item.attr('tcId');
        var template =
            '<div id="cvPopover" class="cv-popover" style="' + dialogStyle + '">' +
            '<div class="cv-course-card cv-setting">' +
            '<div class="cv-operate">' +
            '<div>请选择志愿</div>' +
            '<div class="cv-select cv-flag"></div>' +
            '<div>' +
            '<button class="cv-btn cvBtnFlag" type="sure">选择</button>' +
            '<button class="cv-btn cvBtnFlag" type="cancel">取消</button>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '<div class="cv-popover-position"></div>' +
            '</div>';
        removeDialog();
        var $dialog = $(template);
        $('body').append($dialog);

        eventsListen($dialog, _data, tcId);
    }

    function eventsListen($dialog, _data, tcId) {
        //点击页脚按钮的事件
        $dialog.on('click', '.cvBtnFlag', function() {
            btnHandle($(this), tcId);
        });

        //点击下拉框
        $dialog.on('click', '.cv-select', function() {
            CVDropdownDialog.init($(this), _data, 'volunteer');
        });
    }

    function getItemPositionStyle($item) {
        var dialogHeight = 120;
        var dialogWidth = 192;
        var offset = $item.offset();

        var dialogTop = offset.top - (dialogHeight/2) - 8;
        var dialogLeft = offset.left - dialogWidth - 64;
        var style = 'top: ' + dialogTop + 'px;left: ' + dialogLeft + 'px;';
        return style;
    }

    /**
     * 点击页脚按钮的事件
     * @param $btn 被点击的按钮
     */
    function btnHandle($btn, tcId) {
        var type = $btn.attr('type');
        if (type === 'sure') {
            // 确认选课
            sureHandle($btn, tcId);
        } else {
            // 取消
            cancelHandle();
        }
    }

    /**
     * 取消
     */
    function cancelHandle() {
        removeDialog();
    }

    /**
     * 确认选课
     */
    function sureHandle($btn, tcId) {
        var grade = $('.cv-flag').attr("grade");
        if (grade != null && grade != '') {
            var addParam = buildAddVolunteerParam(tcId, grade);
            addVolunteer(addParam).done(function(resp) {
                var code = resp.code;
                if (code != null && code == '1') {
                    initProcessInterval(function(processResp){
                    	if(processResp.code == '1'){
                    		$.bhTip({
                    			content: '添加选课成功',
                    			state: 'success'
                    		});
                    	}else if(processResp.code == '-1'){
                    		$.bhTip({
                    			content: processResp.msg,
                    			state: 'danger'
                    		});
                    	}
                    	// 刷新表格
                    	reloadTable('1');
                    });
                } else if (code == '302') {
                    sessionStorage.removeItem('token');
                    sessionStorage.removeItem('studentInfo');
                    window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
                } else {
                    var failObj = new Object();
                    failObj.title = '失败';
                    failObj.content = resp.msg;
                    CVDialog.showDanger(failObj);
                }
                removeDialog();
            });
        }
    }

    /**
     * 移除弹框
     */
    function removeDialog() {
        $('#cvPopover').remove();
    }
})(window.CVPopover = window.CVPopover || {});

/**
 * 简单模式的相关事件方法
 */
;
(function(_mode) {

})(window.CVSingleMode = window.CVSingleMode || {}); + function($) {
    'use strict';

    var Tab = function(element) {
        this.element = $(element);
    };

    Tab.prototype.show = function() {
        var $this = this.element;
        var $li = $this.closest('li');
        var $ul = $this.closest('ul');

        if (typeof $this.attr('disabled') !== 'undefined' || $this.parent('li').hasClass('cv-active')) {
            return;
        }

        $ul.children('li.cv-active').removeClass('cv-active');
        $li.addClass('cv-active');

        var target = $this.attr('href');
        var $tab = $ul.closest('[cv-role="tabs"]');
        var $thisContent = $(target);

        $tab.children('.cv-tab-content').children().removeClass('cv-active');
        $thisContent.addClass('cv-active');
    };

    function Plugin(option) {
        return this.each(function() {
            var $this = $(this);
            var data = $this.data('bs.tab');

            if (!data) $this.data('bs.tab', (data = new Tab(this)));
            if (typeof option == 'string') data[option]();
        });
    }
    $.fn.tab = Plugin;
    var clickHandler = function(e) {
        e.preventDefault();
        Plugin.call($(this), 'show');
    };
    $(document)
        .on('click.cv-tabs', '[cv-role="tab"]', clickHandler);

}(jQuery);

// 初始化志愿等级数据
function initVolunteerData() {
    queryVolunteerData().done(function(resp) {
        var code = resp.code;
        if (code == "1") {
            var dataList = resp.dataList;
            var vData = [];
            for (var i = 0, len = dataList.length; i < len; i++) {
                var grade = dataList[i].grade;
                var name = dataList[i].name;
                var classType = "";
                switch (grade) {
                    case 1:
                        classType = "cv-one";
                        break;
                    case 2:
                        classType = "cv-two";
                        break;
                    case 3:
                        classType = "cv-three";
                        break;
                    case 4:
                        classType = "cv-four";
                        break;
                    case 5:
                        classType = "cv-five";
                        break;
                    default:
                        classType = "cv-one";
                }
                var vObj = {
                    class: classType,
                    text: name,
                    grade: grade
                };
                vData.push(vObj);
            }
            volunteerData = vData;
        } else if (code == '302') {
            sessionStorage.removeItem('token');
            sessionStorage.removeItem('studentInfo');
            window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
        } else {
            //console.log("查询志愿等级数据失败");
        }
    });
}

/*
 * 排序事件
 * @param event      点击对象
 * @param courseType 课程类型
 */
function expertModeSorting(event, courseType) {
    var sortType = '';
    var objClass = $(event.target).attr("class");
    if (objClass.indexOf("cv-sort") >= 0) {
        // 初始状态，变为正序
        if (objClass.indexOf('cv-firstVolunteer-col') >= 0) {
            $(event.target).attr("class", "cv-up cv-firstVolunteer-col");
        } else if (objClass.indexOf('cv-class') >= 0) {
            $(event.target).attr("class", "cv-up cv-class");
        } else {
            $(event.target).attr("class", "cv-up");
        }
        sortType = '+';
    } else if (objClass.indexOf("cv-up") >= 0) {
        // 正序状态，变为倒序
        if (objClass.indexOf('cv-firstVolunteer-col') >= 0) {
            $(event.target).attr("class", "cv-down cv-firstVolunteer-col");
        } else if (objClass.indexOf('cv-class') >= 0) {
            $(event.target).attr("class", "cv-down cv-class");
        } else {
            $(event.target).attr("class", "cv-down");
        }
        sortType = '-';
    } else if (objClass.indexOf("cv-down") >= 0) {
        // 倒序状态，变为初始状态
        if (objClass.indexOf('cv-firstVolunteer-col') >= 0) {
            $(event.target).attr("class", "cv-sort cv-firstVolunteer-col");
        } else if (objClass.indexOf('cv-class') >= 0) {
            $(event.target).attr("class", "cv-sort cv-class");
        } else {
            $(event.target).attr("class", "cv-sort");
        }
    }
    if (courseType == 'recommend') {
        // 推荐选课
        recommendOrder = sortType;
        CVRecommendCourse.listReload();
    } else if (courseType == 'public') {
        // 公选选课
        publicOrder = sortType;
        CVPublicCourse.listReload();
    } else if (courseType == 'program') {
        // 方案内选课
        programOrder = sortType;
        CVProgramCourse.listReload();
    } else if (courseType == 'unProgram') {
        // 方案外选课
        unProgramOrder = sortType;
        CVUnProgramCourse.listReload();
    } else if (courseType == 'retake') {
        // 重修选课
        retakeOrder = sortType;
        CVRetakeCourse.listReload();
    } else if (courseType == 'sport') {
        // 体育选课
        sportOrder = sortType;
        CVSportCourse.listReload();
    } else if (courseType == 'minor') {
        // 辅修选课
        minorOrder = sortType;
        CVMinorCourse.listReload();
    }
}

/**
 * 创建查询教学班的请求参数
 */
function buildQueryTCParam(content) {
    content = content == null ? '' : content;
    if(content){
    	content = content.replace(/\\/g, '\\\\').replace(/\"/g, '\\\"');
    }
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo')); //学生信息
    var studentCode = studentInfo.code; // 学号
    // 选课批次
    var electiveBatch = studentInfo.electiveBatch;
    var electiveBatchCode = electiveBatch.code;
    // 当前校区
    var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
    var campus = currentCampus.code; // 校区
    var isMajor = '1'; // 是否主修
    var teachingClassType = sessionStorage.getItem("teachingClassType"); // 教学班类型
    var queryData = '{"studentCode":"' + studentCode + '","campus":"' + campus + '","electiveBatchCode":"' + electiveBatchCode + '","isMajor":"' + isMajor + '","teachingClassType":"' + teachingClassType + '"';
    // 不同课程类型取不同的请求参数
    var pageIndex = null;
    var order = null;
    if (teachingClassType == 'TJKC') {
        // 推荐课程
        pageIndex = recommendPageNumber;
        order = recommendOrder;
        var sfct = $('#recommend_sfct').val();
        var sfym = $('#recommend_sfym').val();
        var kcxz = $('#recommend_kcxz').val();
        var kclb = $('#recommend_kclb').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'FANKC') {
        // 方案内课程
        pageIndex = programPageNumber;
        order = programOrder;
        var sfct = $('#program_sfct').val();
        var sfym = $('#program_sfym').val();
        var kcxz = $('#program_kcxz').val();
        var kclb = $('#program_kclb').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'FAWKC') {
        // 方案外课程
        pageIndex = unProgramPageNumber;
        order = unProgramOrder;
        var sfct = $('#unprogram_sfct').val();
        var sfym = $('#unprogram_sfym').val();
        var kcxz = $('#unprogram_kcxz').val();
        var kclb = $('#unprogram_kclb').val();
        var	nj = $('#unprogram_nj').val();
        var	yx = $('#unprogram_yx').val();
        var	zy = $('#unprogram_zy').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        if (nj) {
        	content = 'ZXNJ:' + nj + ',' + content;
        }
        if (yx) {
        	content = 'ZXYX:' + yx + ',' + content;
        }
        if (zy) {
        	content = 'ZXZY:' + zy + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'XGXK') {
        // 校公选课
        pageIndex = publicPageNumber;
        order = publicOrder;
        var sfct = $('#public_sfct').val();
        var sfym = $('#public_sfym').val();
        var xgxklb = $('#public_xgxklb').val();
        var kcbk = $('#course_section').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (xgxklb != '') {
            if (content != null && content != '') {
                content += ',XGXKLBDM:' + xgxklb;
            } else {
                content = 'XGXKLBDM:' + xgxklb;
            }        
        }
        if (kcbk) {
            if (content != null && content != '') {
                content += ',KCBK:' + kcbk;
            } else {
                content = 'KCBK:' + kcbk;
            }      
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'CXKC') {
        // 重修课程
        pageIndex = retakePageNumber;
        order = retakeOrder;
        var sfct = $('#retake_sfct').val();
        var sfym = $('#retake_sfym').val();
        var kcxz = $('#retake_kcxz').val();
        var kclb = $('#retake_kclb').val();
        var xklx = $('#retake_xklx').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        if (xklx) {
        	content = 'CXCKLX:' + xklx + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'TYKC') {
        // 体育课程
        pageIndex = sportPageNumber;
        order = sportOrder;
        var sfct = $('#sport_sfct').val();
        var sfym = $('#sport_sfym').val();
        var kcxz = $('#sport_kcxz').val();
        var kclb = $('#sport_kclb').val();
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'FXKC') {
        // 辅修课程
        pageIndex = minorPageNumber;
        order = minorOrder;
        isMajor = '0'; // 是否主修
        var sfct = $('#minor_sfct').val();
        var sfym = $('#minor_sfym').val();
        var kcxz = $('#minor_kcxz').val();
        var kclb = $('#minor_kclb').val();
        var nj = '';
    	var yx = '';
    	var zy = '';
        if(!$('.cv-minor-njyxzy').hasClass('cv-block-hide')){
        	nj = $('#minor_nj').val();
        	yx = $('#minor_yx').val();
        	zy = $('#minor_zy').val();
        }
        queryData += ',"checkConflict":"' + sfct + '"';
        queryData += ',"checkCapacity":"' + sfym + '"';
        if (kcxz) {
            content = 'KCXZ:' + kcxz + ',' + content;
        }
        if (kclb) {
            content = 'KCLB:' + kclb + ',' + content;
        }
        if (nj) {
        	content = 'FXNJ:' + nj + ',' + content;
        }
        if (yx) {
        	content = 'FXYX:' + yx + ',' + content;
        }
        if (zy) {
        	content = 'FXZY:' + zy + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    } else if (teachingClassType == 'QXKC') {
        // 全校课程
        pageIndex = schoolPageNumber;
        order = schoolOrder;
        var xgxklb = $('#school_xgxklb').val();
        var kkdw = $('#school_kkdw').val();
        var xflb = $('#school_xflb').val();
        queryData += ',"isMajor":"1"';
        if (xgxklb) {
            content = 'XGXKLBDM:' + xgxklb + ',' + content;
        }
        if (kkdw) {
            content = 'KKDWDM:' + kkdw + ',' + content;
        }
        if (xflb) {
            content = 'XFLB:' + xflb + ',' + content;
        }
        queryData += ',"queryContent":"' + content + '"';
    }
    queryData += '}';
    if (pageIndex == null || pageIndex < 0) {
        pageIndex = 0;
    }
    var queryStr = '{"data":' + queryData + ',"pageSize":"' + pageSize + '","pageNumber":"' + pageIndex + '","order":"' + (order==null?'':order) + '"}';
    var queryParam = {
        'querySetting': queryStr
    };
    return queryParam;
}

/**
 * 创建添加志愿选课参数
 * @param tcid 教学班id
 * @param cv   选择志愿等级   
 */
function buildAddVolunteerParam(tcId, testTeachingClassID, needBook) {
    // 教学班类型
    var tcType = sessionStorage.getItem("teachingClassType");
    // 当前校区
    var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
    var campusCode = currentCampus.code; // 校区
    //学生信息
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var studentCode = studentInfo.code; // 学号
    // 选课批次
    var electiveBatch = studentInfo.electiveBatch;
    var electiveBatchCode = electiveBatch.code;
//    if(needBook === null || needBook === undefined || needBook === ''){
//    	needBook = '';
//    	if($('#sfbook_' + tcId).length > 0){
//    		if($('#sfbook_' + tcId).prop('checked')){
//    			needBook = '1';
//    		}else{
//    			needBook = '0';
//    		}
//    	}
//    }
    var addData = null;
    addData = '{"operationType":"1","studentCode":"'
        + studentCode + '","electiveBatchCode":"'
        + electiveBatchCode + '","teachingClassId":"'
        + tcId + '","isMajor":"1'
        + '","campus":"' + campusCode
        + '","teachingClassType":"' + tcType;
    if(needBook){
    	addData += '","needBook":"' + needBook;
    }
    if (testTeachingClassID != null) {
        addData += '","testTeachingClassID":"' + testTeachingClassID;
    }
    addData += '"}';
    
    var addStr = '{"data":' + addData + '}';
    var appParam = {
        'addParam': addStr
    };
    return appParam;
}

// 菜单控制初始化
function initMenuControl() {
    var currentBatch = JSON.parse(sessionStorage.getItem('currentBatch'));
    var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
    var bookParam = {
		needBook: sysParam.needBook,
		canSelectBook: '0',
		canDeleteBook: '0'
    };
    
    if(sysParam.displayCjMenu == '1'){
    	$('.cvMiniIconFlag[type="score"]').show();
    }else{
    	$('.cvMiniIconFlag[type="score"]').hide();
    }
    
    if(sysParam.needBook == '1'){
    	if(currentBatch.canSelectBook == '1'){
    		bookParam.canSelectBook = '1';
    	}
    	if(currentBatch.canDeleteBook == '1'){
    		bookParam.canDeleteBook = '1';
    	}
    }
    sessionStorage.setItem('bookParam', JSON.stringify(bookParam));
    
    if(sysParam.kclbNotDisplay == '1'){
    	$('.main').addClass('no-kclb');
    }
    
    if(sysParam.displayMajorFlag != '1'){
    	$('.main').addClass('no-zfx');
    }

    if(sysParam.isSplitRetake == '1'){
    	$('.main').addClass('hasSplitRetake');
    }

    var displayTJKC = currentBatch.displayTJKC;
    var displayNameTJKC = sysParam.displayNameTJKC;

    var displayFANKC = currentBatch.displayFANKC;
    var displayNameFANKC = sysParam.displayNameFANKC;

    var displayFAWKC = currentBatch.displayFAWKC;
    var displayNameFAWKC = sysParam.displayNameFAWKC;

    var displayCXKC = currentBatch.displayCXKC;
    var displayNameCXKC = sysParam.displayNameCXKC;

    var displayTYKC = currentBatch.displayTYKC;
    var displayNameTYKC = sysParam.displayNameTYKC;

    var displayXGXK = currentBatch.displayXGXK;
    var displayNameXGXK = sysParam.displayNameXGXK;

    var displayFX = currentBatch.displayFX;
    var displayNameFX = sysParam.displayNameFX;
    
    var displayALLKC = currentBatch.displayALLKC;
    var displayNameALLKC = sysParam.displayNameALLKC;

    var initTab = '';

    if (displayTJKC != null && displayTJKC == '1') {
        var $tab = $("#aRecommendCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameTJKC);
        initTab = 'recommend';
    }else if(displayNameTJKC){
    	$("#aRecommendCourse").html(displayNameTJKC);
    }
    if (displayFANKC != null && displayFANKC == '1') {
        var $tab = $("#aProgramCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameFANKC);
        if (initTab == '') {
            initTab = 'program';
        }
    }else if(displayNameFANKC){
    	$("#aProgramCourse").html(displayNameFANKC);
    }
    if (displayFAWKC != null && displayFAWKC == '1') {
        var $tab = $("#aUnProgramCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameFAWKC);
        if (initTab == '') {
            initTab = 'unprogram';
        }
    }else if(displayNameFAWKC){
    	$("#aUnProgramCourse").html(displayNameFAWKC);
    }
    if (displayCXKC != null && displayCXKC == '1') {
        var $tab = $("#aRetakeCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameCXKC);
        if (initTab == '') {
            initTab = 'retake';
        }
    }else if(displayNameCXKC){
    	$("#aRetakeCourse").html(displayNameCXKC);
    }
    if (displayTYKC != null && displayTYKC == '1') {
        var $tab = $("#aSportCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameTYKC);
        if (initTab == '') {
            initTab = 'sport';
        }
    }else if(displayNameTYKC){
    	$("#aSportCourse").html(displayNameTYKC);
    }
    if (displayXGXK != null && displayXGXK == '1') {
        var $tab = $("#aPublicCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameXGXK);
        if (initTab == '') {
            initTab = 'public';
        }
    }else if(displayNameXGXK){
    	$("#aPublicCourse").html(displayNameXGXK);
    }
    if (displayFX != null && displayFX == '1') {
        var $tab = $("#aMinorCourse");
        $tab.removeAttr("disabled");
        $tab.html(displayNameFX);
        if (initTab == '') {
            initTab = 'minor';
        }
        if(sysParam.displayAllFX != '1'){
        	$('#cvMinorCourse .cv-minor-njyxzy').addClass('cv-block-hide');
        }
    }else if(displayNameFX){
    	$("#aMinorCourse").html(displayNameFX);
    }
    if (displayALLKC != null && displayALLKC == '1') {
    	var $tab = $("#aSchoolCourse");
    	$tab.removeAttr("disabled");
    	$tab.html(displayNameALLKC);
    	if (initTab == '') {
    		initTab = 'school';
    	}
    }else if(displayNameALLKC){
    	$("#aSchoolCourse").html(displayNameALLKC);
    }

    var teachingClassType = '';
    if (initTab == 'recommend') {
        // 初始化推荐选课
        teachingClassType = $("#aRecommendCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVRecommendCourse.listInit();
        $('#cvRecommendCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aRecommendCourse').parent().addClass('cv-active');
    } else if (initTab == 'program') {
        // 初始化方案内选课
        teachingClassType = $("#aProgramCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVProgramCourse.listInit();
        $('#cvProgramCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aProgramCourse').parent().addClass('cv-active');
    } else if (initTab == 'unprogram') {
        // 初始化方案外选课
        teachingClassType = $("#aUnProgramCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVUnProgramCourse.listInit();
        $('#cvUnProgramCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aUnProgramCourse').parent().addClass('cv-active');
    } else if (initTab == 'retake') {
        // 初始化重修选课
        teachingClassType = $("#aRetakeCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVRetakeCourse.listInit();
        $('#cvRetakeCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aRetakeCourse').parent().addClass('cv-active');
    } else if (initTab == 'sport') {
        // 初始化体育选课
        teachingClassType = $("#aSportCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVSportCourse.listInit();
        $('#cvSportCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aSportCourse').parent().addClass('cv-active');
    } else if (initTab == 'public') {
        // 初始化校公选课选课
        teachingClassType = $("#aPublicCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVPublicCourse.listInit();
        $('#cvPublicCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aPublicCourse').parent().addClass('cv-active');
    } else if (initTab == 'minor') {
        // 初始化辅修选课
        teachingClassType = $("#aMinorCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVMinorCourse.listInit();
        $('#cvMinorCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aMinorCourse').parent().addClass('cv-active');
    } else if (initTab == 'school') {
        // 初始化辅修课选课
        teachingClassType = $("#aSchoolCourse").attr("teachingClassType");
        sessionStorage.setItem("teachingClassType", teachingClassType);
        CVSchoolCourse.listInit();
        $('#aSchoolCourse').attr('class', ' cv-pb-38');
        // 设置选中样式
        $('#aSchoolCourse').parent().addClass('cv-active');
    } else {
        // 未开放选课，数据有问题
    }
    var mainWidth = $('#cvPageHeadTab').width() + 480;
    if(mainWidth < 1000){
    	mainWidth = 1000;
    }
    $('body>.main').css({'min-width': mainWidth});
    
    if(sysParam.xgxkQueryTitle){
    	changeTskName(sysParam.xgxkQueryTitle);
    }
}

/**
 * 课程列表翻页
 */
function pagingCourse(sortType, courseType) {
    if (courseType == 'recommend' && recommendTotalPage > 1) {
        //推荐选课翻页
        if (sortType == "up" && recommendPageNumber > 0) {
            recommendPageNumber = recommendPageNumber - 1;
            CVRecommendCourse.listReload();
        } else if (sortType == "down" && recommendPageNumber < (recommendTotalPage - 1)) {
            recommendPageNumber = recommendPageNumber + 1;
            CVRecommendCourse.listReload();
        }
    } else if (courseType == 'program') {
        //方案内选课翻页
        if (sortType == "up" && programPageNumber > 0) {
            programPageNumber = programPageNumber - 1;
            CVProgramCourse.listReload();
        } else if (sortType == "down" && programPageNumber < (programTotalPage - 1)) {
            programPageNumber = programPageNumber + 1;
            CVProgramCourse.listReload();
        }
    } else if (courseType == 'unProgram') {
        //方案外选课翻页
        if (sortType == "up" && unProgramPageNumber > 0) {
            unProgramPageNumber = unProgramPageNumber - 1;
            CVUnProgramCourse.listReload();
        } else if (sortType == "down" && unProgramPageNumber < (unProgramTotalPage - 1)) {
            unProgramPageNumber = unProgramPageNumber + 1;
            CVUnProgramCourse.listReload();
        }
    } else if (courseType == 'public') {
        //公选课选课翻页
        if (sortType == "up" && publicPageNumber > 0) {
            publicPageNumber = publicPageNumber - 1;
            CVPublicCourse.listReload();
        } else if (sortType == "down" && publicPageNumber < (publicTotalPage - 1)) {
            publicPageNumber = publicPageNumber + 1;
            CVPublicCourse.listReload();
        }
    } else if (courseType == 'retake') {
        //重修选课翻页
        if (sortType == "up" && retakePageNumber > 0) {
            retakePageNumber = retakePageNumber - 1;
            CVRetakeCourse.listReload();
        } else if (sortType == "down" && retakePageNumber < (retakeTotalPage - 1)) {
            retakePageNumber = retakePageNumber + 1;
            CVRetakeCourse.listReload();
        }
    } else if (courseType == 'sport') {
        //体育选课翻页
        if (sortType == "up" && sportPageNumber > 0) {
            sportPageNumber = sportPageNumber - 1;
            CVSportCourse.listReload();
        } else if (sortType == "down" && sportPageNumber < (sportTotalPage - 1)) {
            sportPageNumber = sportPageNumber + 1;
            CVSportCourse.listReload();
        }
    } else if (courseType == 'minor') {
        // 辅修选课翻页
        if (sortType == "up" && minorPageNumber > 0) {
            minorPageNumber = minorPageNumber - 1;
            CVMinorCourse.listReload();
        } else if (sortType == "down" && minorPageNumber < (minorTotalPage - 1)) {
            minorPageNumber = minorPageNumber + 1;
            CVMinorCourse.listReload();
        }
    } else if (courseType == "school") {
        // 全校课程翻页
        if (sortType == "up" && schoolPageNumber > 0) {
            schoolPageNumber = schoolPageNumber - 1;
            CVSchoolCourse.listReload();
        } else if (sortType == "down" && schoolPageNumber < (schoolTotalPage - 1)) {
            schoolPageNumber = schoolPageNumber + 1;
            CVSchoolCourse.listReload();
        }
    }
}

/**
 * 重载当前选中页面的列表
 */
function reloadTable(isCurrentPage, tcId) {
    var teachingClassType = sessionStorage.getItem("teachingClassType");
    if (teachingClassType == 'TJKC') {
        // 推荐课程
        recommendPageNumber = 0;
        CVRecommendCourse.listInit(true, tcId);
    } else if (teachingClassType == 'FANKC') {
        // 方案内课程
        programPageNumber = 0;
        CVProgramCourse.listInit();
    } else if (teachingClassType == 'FAWKC') {
        // 方案外课程
        unProgramPageNumber = 0;
        CVUnProgramCourse.listInit(true, tcId);
    } else if (teachingClassType == 'XGXK') {
        // 校公选课
        publicPageNumber = 0;
        CVPublicCourse.listInit();
    } else if (teachingClassType == 'CXKC') {
        // 重修课程
        retakePageNumber = 0;
        CVRetakeCourse.listInit();
    } else if (teachingClassType == 'TYKC') {
        // 体育课程
        sportPageNumber = 0;
        CVSportCourse.listInit();
    } else if (teachingClassType == 'FXKC') {
        // 辅修课程
        minorPageNumber = 0;
        CVMinorCourse.listInit();
    } else if (teachingClassType == 'QXKC') {
        // 全校课程
    	schoolPageNumber = 0;
    	CVSchoolCourse.listInit();
    }
}

/**
 * 绑定退课日志链接点击事件
 */
function departureLogClickBinding() {
    $('#elective-log').on('click', function(resp) {
        window.open(BaseUrl + '/sys/xsxkapp/*default/departurelog.do');
    });
}

function searchClickBinding() {
    $('.cv-search-input').bind('keyup', function(event) {
        if (event.keyCode == "13") {
            var courseType = $(event.currentTarget).attr('courseType');
            if (courseType == 'FAWKC') {
                unProgramPageNumber = 0;
                CVUnProgramCourse.listReload();
            } else if (courseType == 'TJKC') {
                recommendPageNumber = 0;
                CVRecommendCourse.listReload();
            } else if (courseType == 'FANKC') {
                programPageNumber = 0;
                CVProgramCourse.listReload();
            } else if (courseType == 'XGXK') {
                publicPageNumber = 0;
                CVPublicCourse.listReload();
            } else if (courseType == 'CXKC') {
                retakePageNumber = 0;
                CVRetakeCourse.listReload();
            } else if (courseType == 'TYKC') {
                sportPageNumber = 0;
                CVSportCourse.listReload();
            } else if (courseType == 'FXKC') {
                minorPageNumber = 0;
                CVMinorCourse.listReload();
            } else if (courseType == 'QXKC') {
                schoolPageNumber = 0;
                CVSchoolCourse.listReload();
            }
        }
    });

    $('#cv-log-img').on('click', function(e) {
        window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
    });
}

/**
 * 引导页
 */
;(function (_guideMap) {

    _guideMap.init = function() {
        initGuideMap();
    };

    function initGuideMap() {
        queryIsReadGuideMap().done(function(resp){
            var code = resp.code;
            if (code != null && code == '2') {
                // 未读
                showStep();
                setReadGuideMap();
            } else {
                // 已读
                hideStep();
                remindUnSuccessfulCourse();
            }
        });
    }

    function setReadGuideMap() {
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code;
        BH_UTILS.doAjax(
            BaseUrl + "/sys/xsxkapp/student/guideMap.do?studentCode=" + studentCode,
            {},
            "post",
            {},
            {"token" : sessionStorage.token}
        );
    }

    function showStep() {
        // 显示
        $(".jszp").height($('body').height() - 100);
        $(".jszp .btns").css('padding-left', ($('body').width() - $('.main').width())/2);
        $(".jszp .step1 .cv-btn").click(function(){
            $(".jszp .step1").hide();
            $(".jszp .step2").show();
        });
        $(".jszp .step2 .cv-btn").click(function(){
            $(".jszp").remove();
            remindUnSuccessfulCourse();
        });
        sessionStorage.setItem('isInitStep', '1');

        $(".jszp").css('display', '');  
    }

    function hideStep() {
        // 隐藏
        $(".jszp").css('display', 'none');
    }

    function queryIsReadGuideMap() {
        var timestamp = new Date().getTime();
        var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
        var studentCode = studentInfo.code;
        return BH_UTILS.doAjax(
            BaseUrl + "/sys/xsxkapp/student/guideMap.do?timestamp=" + timestamp + "&studentCode=" + studentCode,
            {},
            "get",
            {},
            {"token" : sessionStorage.token}
        );
    }

})(window.CVGuideMap = window.CVGuideMap || {});

/**
 * 提醒落选课程
 */
function remindUnSuccessfulCourse() {
	var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
	if(sysParam.noDisplayVolunteer == '1'){
		$('.cvMiniIconFlag[type="unsuccessful"]').css('display', 'none');
		return;
	}
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var studentCode = studentInfo.code;
    var isRead = '0';
    queryUnSuccessful(studentCode, isRead, studentInfo.electiveBatch.code).done(function(resp){
        var code = resp.code;
        if (code != null && code == '1') {
            var dataList = resp.dataList;
            var length = dataList.length;
            var wids = '';
            //console.log(document.body.scrollHeight);
            if (length > 0) {
                var tableHtml = '<table class="lxTable" style="width:100%"><tr class="thtr"><td style="width:150px;"><h6>日期</h6></td><td style="width: 400px;"><h6>课程名称</h6></td><td><h6>上课教师</h6></td><td style="width: 150px;"><h6>选课结果</h6></td></tr>';
                for (var i = 0; i < length; i++) {
                    wids += dataList[i].wid + ',';
                    var date = dataList[i].deleteOperateTime;
                    date = date.substring(0, 10);
                    var courseName = dataList[i].courseName;
                    var courseIndex = dataList[i].courseIndex;
                    if (courseIndex != null && courseIndex != '') {
                        courseName += '[' + courseIndex + ']';
                    }
                    var sportName = dataList[i].sportName;
                    var engpName = dataList[i].engpName;
                    if (sportName != null && sportName != '') {
                        courseName += '(' + sportName + ')';
                    }else if (engpName != null && engpName != '') {
                        courseName += '(' + engpName + ')';
                    }
                    var teacherName = dataList[i].teacherName;
                    if (teacherName == null) {
                        teacherName = '-';
                    }
                    if (courseName == null) {
                        courseName = '-';
                    }
                    var result = dataList[i].deleteOperateTypeName;
                    tableHtml += '<tr><td>' + date + '</td><td style="width: 400px;">' + courseName + '</td><td>' + teacherName + '</td><td class="color-danger">' + result + '</td></tr>';
                }
                tableHtml += '</table>';
                var html = '<div class="tbTitle">你有' + length + '门课程落选，您也可在侧边栏查看落选详情</div><div>' + tableHtml +'</div>';
                var height = document.body.scrollHeight;
                var $dom  = null;
                $dom = BH_UTILS.bhWindow(html, '落选课程提醒',[
                        {
                            text:'确认',className:'cv-btn bh-btn-primary',
                            callback:function(){
                                submitUnSuccessful(studentCode, wids).done(function(resp){
                                    var code = resp.code;
                                    if (code != null && code == '1') {
                                        $.bhTip({
                                            content: '已确认落选课程',
                                            state: 'success'
                                        });
                                    }
                                    $dom.jqxWindow('close');
                                });   
                                return false;                             
                            }
                        }
                    ], {
                    width: 1000,
                    maxHeight: 1000,
                    maxWidth: 1200
                });
                
                $('.jqx-window-modal').css('height', height);
            }
        } else if (code == '302') {
            sessionStorage.removeItem('token');
            sessionStorage.removeItem('studentInfo');
            window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
        }
    });
}

// 查询已选志愿数量
function querySelectCourseNum() {
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var studentCode = studentInfo.code; // 学号
    var queryParam = {
        'studentCode': studentCode,
        'electiveBatchCode':studentInfo.electiveBatch.code
    };
    queryChooseCourse(queryParam).done(function(resp) {
        var len = 0;
        var code = resp.code;
        if (code != null && code == '1') {
            var dataList = resp.dataList;
            if (dataList != null) {
            	for(var i = 0; i < dataList.length; i++){
            		if(dataList[i].isTest != '1'){
            			len++;
            		}
            	}
            }
        }
        $('#selectcourse_num').html(len);
    });
}

/**
 * 刷新教学班课容量
 */
function flushTeachingClassCapacity(tcId, capacitySuffix) {
    var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    var xh = studentInfo.code;
    if (tcId) {
        queryTeachingClassCapacity(tcId, xh, capacitySuffix).done(function(resp){
            var code = resp.code;
            if (code != null && code == '1') {
                var data = resp.data;
                var numberOfSelected = data.numberOfSelected;
        		var classCapacity = data.classCapacity;
        		var remainingCapacity = '';
        		var limitGender = data.limitGender;
        		if (limitGender == null) {
        			limitGender = '0';
        		}
        		var capacityOfMale = data.capacityOfMale;
        		var capacityOfFemale = data.capacityOfFemale;
        		var numberOfMale = data.numberOfMale;
        		var numberOfFemale = data.numberOfFemale;
        		
                var teachingClassType = sessionStorage.getItem("teachingClassType"); // 教学班类型
            	if(teachingClassType == 'XGXK'){
            		var $btn = $('.cv-choice[tcid="' + tcId + '"');
            		var $row = $btn.closest('.cv-row');
                    if (parseInt(numberOfSelected) >= parseInt(classCapacity)) {
                    	numberOfSelected = '<button class="cv-btn cv-tag cv-danger" type="button">人数已满</button>';
                    }
                    $row.find('.cv-firstVolunteer-col').html(numberOfSelected);
                    $btn.attr("capacityOfMale", capacityOfMale);
                    $btn.attr("capacityOfFemale", capacityOfFemale);
                    $btn.attr("numberOfMale", numberOfMale);
                    $btn.attr("numberOfFemale", numberOfFemale);
            	}else{
            		var $div = $("#" + tcId + "_capacity");
            		var $courseDiv = $("#" + tcId + "_courseDiv");
            		
            		if (parseInt(numberOfSelected) < parseInt(classCapacity)) {
            			remainingCapacity += numberOfSelected + "/" + classCapacity + ' 可选';
            			if($courseDiv.length > 0){ //卡片模式
            				$courseDiv.attr("isfull", "0");
            				$courseDiv.attr("capacityOfMale", capacityOfMale);
            				$courseDiv.attr("capacityOfFemale", capacityOfFemale);
            				$courseDiv.attr("numberOfMale", numberOfMale);
            				$courseDiv.attr("numberOfFemale", numberOfFemale);
            				$courseDiv.find(".cv-isfull").html("");
            				$courseDiv.find(".cv-isfull").attr("class", "cv-btn cv-tag cv-danger cv-isfull cv-block-hide");
            			}
            		} else {
            			remainingCapacity += classCapacity + ' 不可选';
            			if($courseDiv.length > 0){ //卡片模式
            				$courseDiv.attr("isfull", "1");
            				$courseDiv.attr("capacityOfMale", capacityOfMale);
            				$courseDiv.attr("capacityOfFemale", capacityOfFemale);
            				$courseDiv.attr("numberOfMale", numberOfMale);
            				$courseDiv.attr("numberOfFemale", numberOfFemale);
            				$courseDiv.find(".cv-isfull").html("人数已满");
            				$courseDiv.find(".cv-isfull").attr("class", "cv-btn cv-tag cv-danger cv-isfull");
            			}
            		}
            		if(limitGender == 1){
            			if(parseInt(capacityOfMale) > 0){
            				remainingCapacity += '<span style="display: inline-block;margin-left: 5px;">';
            				if(parseInt(numberOfMale) < parseInt(capacityOfMale)){
            					remainingCapacity += numberOfMale + '/' + capacityOfMale + '(男)';
            				}else{
            					remainingCapacity += '男生已满';
            				}
            				remainingCapacity += '</span>';
            			}
            			if(parseInt(capacityOfFemale) > 0){
            				remainingCapacity += '<span style="display: inline-block;margin-left: 5px;">';
            				if(parseInt(numberOfFemale) < parseInt(capacityOfFemale)){
            					remainingCapacity += numberOfFemale + '/' + capacityOfFemale + '(女)';
            				}else{
            					remainingCapacity += '女生已满';
            				}
            				remainingCapacity += '</span>';
            			}
            		}
            		$div.html(remainingCapacity);
            	}
                
            }
        });
    }    
}

function reloadCourseList(tcId, capacitySuffix) {
    var tcType = sessionStorage.getItem("teachingClassType");
    if (tcType == 'FAWKC') {
        CVUnProgramCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'TJKC') {
        CVRecommendCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'FANKC') {
        CVProgramCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'XGXK') {
    	publicPageNumber = 0;
        CVPublicCourse.listReload(tcId, capacitySuffix);
    } else if (tcType == 'CXKC') {
        CVRetakeCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'TYKC') {
        CVSportCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'FXKC') {
        CVMinorCourse.listReload(true, tcId, capacitySuffix);
    } else if (tcType == 'QXKC') {
    	CVSchoolCourse.listReload();
    }
}

/**
 * 在线人数提醒
 */
;(function (_online) {

    _online.init = function() {
        var $tip = $('#noline-tip');
        setOnlinTip($tip);
    };

    function setOnlinTip($tip) {
        queryOnlineUsers().done(function(resp){
            var code = resp.code;
            if(code != null && code == '1') {
                var data = resp.data;
                var onlineUsers = data.onlineUsers;
                $tip.html('（当前选课在线人数 ' + onlineUsers + '人）');
            }
        });
    };

})(window.CVOnlineTip = window.CVOnlineTip || {});

/**
 * 绑定事件
 */
;(function (_binding) {

    _binding.init = function() {
        bindLogOutClick();
        bindChangeCampus();
        bindGoHome();
    };

    function bindLogOutClick() {
        var $logout = $('#logout');
        //$logout.hide();
        $logout.on('click', function(event){
            var stundentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));//学生信息
            if(stundentInfo != null) {
                var dialogData = new Object();
                dialogData.title = '确定退出';
                dialogData.content = '确定退出系统吗？';
                CVDialog.showLogOut(dialogData);
            }
        });
    } 
    
    function bindGoHome(){
    	$('#goHome').off('click').on('click', function(){
    		window.location.href = BaseUrl + "/sys/xsxkapp/*default/index.do";
    	});
    }

    function bindChangeCampus() {
    	var studentInfo = JSON.parse(sessionStorage.getItem('studentInfo'));
    	var multiCampus = studentInfo.electiveBatch.multiCampus;
    	var multiTeachCampus = studentInfo.electiveBatch.multiTeachCampus;
    	if((multiCampus != null && multiCampus == '1') || (multiTeachCampus != null && multiTeachCampus == '1')) {
    		$('body').off('click', '.home-change-campus').on('click','.home-change-campus', function(e){
    			e.stopPropagation();
            	e.preventDefault();
    			var campusList = JSON.parse(sessionStorage.getItem('campusList'));
    			if(multiTeachCampus == null || multiTeachCampus=='0'){
    				campusList = campusList.filter(function(item) {
    					return studentInfo.teachCampus == item.reserve2;
    				});
    			}
    			initCampusList(campusList, e);
    		});
    	}
    }
    
    function initCampusList(_data, e){
    	var position = $(e.currentTarget).offset();
        var left = position.left - 100;
        var top = position.top + 20;
        var template =
            '<div class="cv-dropdown-dialog" style="padding: 10px 0;border-radius: 10px;overflow-y: auto;top:' + top + 'px;left:' + left + 'px;width: 200px;max-height: 350px;">';
        var campus = null;
        for (var i = 0, length = _data.length; i < length; i++) {
            campus = _data[i];
            template += '<div class="campusListHome" code=' + campus.code + '>' + campus.name + '</div>';
        }
        template += '</div>';
        var $body = $('body');
        CVDropdownDialog.remove();
        CVDialog.unScroll(); //阻止页面滚动
        $body.append(template);
        // 绑定校区下拉点击触发事件
        $('.campusListHome').off('click').on('click', function(e) {
        	CVDropdownDialog.remove();
        	CVDialog.restoreScroll(); //恢复页面滚动
            // 当前校区
            var currentCampus = JSON.parse(sessionStorage.getItem('currentCampus'));
            // 新选择的校区
            var code = $(e.currentTarget).attr('code');
            var name = $(e.currentTarget).text();
            // 切换不同的校区（1：更新当前校区 2：更新页面列表数据）
            if (currentCampus != null && currentCampus.code != code) {
                var currentCampus = {
                    'code': code,
                    'name': name
                };
                sessionStorage.setItem('currentCampus', JSON.stringify(currentCampus));
                reloadTable('0');
            }
        });
    }

})(window.CVBindingEvents = window.CVBindingEvents || {});

/**
 * 绑定search数据和事件
 */
;(function (_search) {

    _search.initSearch = function() {
        initKcxz();
        if(!$('.main').hasClass('no-kclb')){
        	initKclb();
        };
        initXgxklb();
        initCourseSection();
        initKkdw();
        if(!$('.cv-minor-njyxzy').hasClass('cv-block-hide')){
        	initNj();
        	initYx();
        }
        initSknj();
    	initSkyx();
        bindSfSearch();
        bindXklxSearch();
    };

    // 初始化开课单位
    function initKkdw() {
        var dictionary = JSON.parse(sessionStorage.getItem('dictionary'));
        var kkdwArray = dictionary.KKDW;
        if (kkdwArray != null && kkdwArray.length > 0) {
            var $search_kkdw = $(".search_kkdw");
            var kkdw_html = "";
            var kkdw = null;
            for (var i = 0, kkdwLength = kkdwArray.length; i < kkdwLength; i++) {
                kkdw = kkdwArray[i];
                kkdw_html += '<option value="' + kkdw.code + '">' + kkdw.name + '</option>';
            }
            $search_kkdw.append(kkdw_html);
            searchBinding($search_kkdw);
        }
    }

    function initKcxz() {
        var dictionary = JSON.parse(sessionStorage.getItem('dictionary'));
        var kcxzArray = dictionary.KCXZ;
        if (kcxzArray != null && kcxzArray.length > 0) {
            var $search_kcxz = $(".search_kcxz");
            var kcxz_html = "";
            var kcxz = null;
            for (var i = 0, kcxzLength = kcxzArray.length; i < kcxzLength; i++) {
                kcxz = kcxzArray[i];
                kcxz_html += '<option value="' + kcxz.code + '">' + kcxz.name + '</option>';
            }
            $search_kcxz.append(kcxz_html);
            searchBinding($search_kcxz);
        }
    }

    function initKclb() {
        var dictionary = JSON.parse(sessionStorage.getItem('dictionary'));
        var kclbArray = dictionary.KCLB;
        if (kclbArray != null && kclbArray.length > 0) {
            var $search_kclb = $(".search_kclb");
            var kclb_html = "";
            var kclb = null;
            for (var i = 0, kclbLength = kclbArray.length; i < kclbLength; i++) {
                kclb = kclbArray[i];
                kclb_html += '<option value="' + kclb.code + '">' + kclb.name + '</option>';
            }
            $search_kclb.append(kclb_html);   
            searchBinding($search_kclb);         
        }
    }

    function initXgxklb() {
        var dictionary = JSON.parse(sessionStorage.getItem('dictionary'));
        var xgxklbArray = dictionary.XGXKLB;
        if (xgxklbArray != null && xgxklbArray.length > 0) {
            var $search_xgxklb = $(".search_xgxklb");
            var xgxklb_html = "";
            var xgxklb = null;
            for (var i = 0, xgxklbLength = xgxklbArray.length; i < xgxklbLength; i++) {
                xgxklb = xgxklbArray[i];
                xgxklb_html += '<option value="' + xgxklb.code + '">' + xgxklb.name + '</option>';
            }
            $search_xgxklb.append(xgxklb_html);
            searchBinding($search_xgxklb);
        }        
    }
    
    function initNj() {
    	queryYxNjZyData('nj').done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
                var dataListTmp = JSON.parse(resp.msg);
                var j = null;
                var dataList = [];
                for(j in dataListTmp){
                	dataList.push({
                		code: j,
                		name: dataListTmp[j]
                	});
                }
                dataList.sort(function(a, b){
                	return b.code - a.code;
                });
                dataList.unshift({
    				code: '',
    				name: '请选择'
    			});
                var $search_nj = $("#minor_nj");
                var nj_html = "";
                var nj = null;
                for (var i = 0, njLength = dataList.length; i < njLength; i++) {
                    nj = dataList[i];
                    nj_html += '<option value="' + nj.code + '">' + nj.name + '</option>';
                }
                $search_nj.html(nj_html);
                searchBinding($search_nj);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectMinorCourse').html(resp.msg);
            }
        });  
    }
 
    function initYx() {
    	queryYxNjZyData('yx').done(function(resp) {
            var code = resp.code;
            if (code != null && code == '1') {
            	var dataListTmp = JSON.parse(resp.msg);
                var j = null;
                var dataList = [{
    				code: '',
    				name: '请选择'
    			}];
                for(j in dataListTmp){
                	dataList.push({
                		code: j,
                		name: dataListTmp[j]
                	});
                }
                var $search_yx = $("#minor_yx");
                var yx_html = "";
                var yx = null;
                for (var i = 0, yxLength = dataList.length; i < yxLength; i++) {
                    yx = dataList[i];
                    yx_html += '<option value="' + yx.code + '">' + yx.name + '</option>';
                }
                $search_yx.html(yx_html);
                searchBinding($search_yx);
            } else if (code == '302') {
                sessionStorage.removeItem('token');
                sessionStorage.removeItem('studentInfo');
                window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
            } else {
                $('#cvCanSelectMinorCourse').html(resp.msg);
            }
        });     
    }
    
    function initZy() {
    	if($('#minor_nj').val() && $('#minor_yx').val()){
    		queryYxNjZyData('zy').done(function(resp) {
    			var yxValue = $('#minor_yx').val();
    			var njValue = $('#minor_nj').val();
    			var code = resp.code;
    			if (code != null && code == '1') {
    				var dataListTmp = JSON.parse(resp.msg);
    				var j = null;
    				var dataList = [{
    					code: '',
    					name: '请选择'
    				}];
    				for(j in dataListTmp){
    					if(yxValue == dataListTmp[j].FXYX && njValue == dataListTmp[j].FXNJ){
    						dataList.push({
    							code: j,
    							name: dataListTmp[j].FXZYMC
    						});
    					}
    				}
    				var $search_zy = $("#minor_zy");
    				var zy_html = "";
    				var zy = null;
    				for (var i = 0, zyLength = dataList.length; i < zyLength; i++) {
    					zy = dataList[i];
    					zy_html += '<option value="' + zy.code + '">' + zy.name + '</option>';
    				}
    				$search_zy.html(zy_html);
    				searchBinding($search_zy);
    			} else if (code == '302') {
    				sessionStorage.removeItem('token');
    				sessionStorage.removeItem('studentInfo');
    				window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
    			} else {
    				$('#cvCanSelectMinorCourse').html(resp.msg);
    			}
    		});     
    	}else{
    		$("#minor_zy").html('<option value="">请选择</option>');
    	}
    }
    
    function initSknj() {
    	querySkYxNjZyData('nj').done(function(resp) {
    		var code = resp.code;
    		if (code != null && code == '1') {
    			var dataListTmp = JSON.parse(resp.msg);
    			var j = null;
    			var dataList = [];
    			for(j in dataListTmp){
    				dataList.push({
    					code: j,
    					name: dataListTmp[j]
    				});
    			}
    			dataList.sort(function(a, b){
    				return b.code - a.code;
    			});
    			dataList.unshift({
    				code: '',
    				name: '请选择'
    			});
    			var $search_nj = $("#unprogram_nj");
    			var nj_html = "";
    			var nj = null;
    			for (var i = 0, njLength = dataList.length; i < njLength; i++) {
    				nj = dataList[i];
    				nj_html += '<option value="' + nj.code + '">' + nj.name + '</option>';
    			}
    			$search_nj.html(nj_html);
    			searchBinding($search_nj);
    		} else if (code == '302') {
    			sessionStorage.removeItem('token');
    			sessionStorage.removeItem('studentInfo');
    			window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
    		} else {
    			$('#cvCanSelectMinorCourse').html(resp.msg);
    		}
    	});  
    }
    
    function initSkyx() {
    	querySkYxNjZyData('yx').done(function(resp) {
    		var code = resp.code;
    		if (code != null && code == '1') {
    			var dataListTmp = JSON.parse(resp.msg);
    			var j = null;
    			var dataList = [{
    				code: '',
    				name: '请选择'
    			}];
    			for(j in dataListTmp){
    				dataList.push({
    					code: j,
    					name: dataListTmp[j]
    				});
    			}
    			var $search_yx = $("#unprogram_yx");
    			var yx_html = "";
    			var yx = null;
    			for (var i = 0, yxLength = dataList.length; i < yxLength; i++) {
    				yx = dataList[i];
    				yx_html += '<option value="' + yx.code + '">' + yx.name + '</option>';
    			}
    			$search_yx.html(yx_html);
    			searchBinding($search_yx);
    		} else if (code == '302') {
    			sessionStorage.removeItem('token');
    			sessionStorage.removeItem('studentInfo');
    			window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
    		} else {
    			$('#cvCanSelectMinorCourse').html(resp.msg);
    		}
    	});     
    }
    
    function initSkzy() {
    	if($('#unprogram_nj').val() && $('#unprogram_yx').val()){
    		querySkYxNjZyData('zy').done(function(resp) {
    			var yxValue = $('#unprogram_yx').val();
    			var njValue = $('#unprogram_nj').val();
    			var code = resp.code;
    			if (code != null && code == '1') {
    				var dataListTmp = JSON.parse(resp.msg);
    				var j = null;
    				var dataList = [{
    					code: '',
    					name: '请选择'
    				}];
    				for(j in dataListTmp){
    					if(yxValue == dataListTmp[j].ZXYX && njValue == dataListTmp[j].ZXNJ){
    						dataList.push({
    							code: j,
    							name: dataListTmp[j].ZXZYMC
    						});
    					}
    				}
    				var $search_zy = $("#unprogram_zy");
    				var zy_html = "";
    				var zy = null;
    				for (var i = 0, zyLength = dataList.length; i < zyLength; i++) {
    					zy = dataList[i];
    					zy_html += '<option value="' + zy.code + '">' + zy.name + '</option>';
    				}
    				$search_zy.html(zy_html);
    				searchBinding($search_zy);
    			} else if (code == '302') {
    				sessionStorage.removeItem('token');
    				sessionStorage.removeItem('studentInfo');
    				window.location.href = BaseUrl + '/sys/xsxkapp/*default/index.do';
    			} else {
    				$('#cvCanSelectMinorCourse').html(resp.msg);
    			}
    		});     
    	}else{
    		$("#unprogram_zy").html('<option value="">请选择</option>');
    	}
    }

    // 初始化课程板块
    function initCourseSection() {
        var sysParam = JSON.parse(sessionStorage.getItem('sysParam'));
        // 是否展示课程板块
        var displayCourseSection = sysParam.displayCourseSection;
        if (displayCourseSection != null && displayCourseSection == '1') {
            var dictionary = JSON.parse(sessionStorage.getItem('dictionary'));
            var kcbkArray = dictionary.KCBK;
            if (kcbkArray != null && kcbkArray.length > 0) {
                var $search_course_section = $(".search_course_section");
                var kcbk_html = "";
                var kcbk = null;
                for (var i = 0, kcbkLength = kcbkArray.length; i < kcbkLength; i++) {
                    kcbk = kcbkArray[i];
                    kcbk_html += '<option value="' + kcbk.code + '">' + kcbk.name + '</option>';
                }
                $search_course_section.append(kcbk_html);
                searchBinding($search_course_section);
            }    
        } else {
            $('#course_label').remove();
            $('#course_section').remove();
        }      
    }

    function bindSfSearch() {
        var $search_sfct = $('.search_sfct');
        var $search_sfym = $('.search_sfym');
        //var $search_sfmooc = $('.search_sfmooc');
        searchBinding($search_sfct);
        searchBinding($search_sfym);
        //searchBinding($search_sfmooc);
    }
    
    function bindXklxSearch() {
    	var $search_xklx = $('.search_xklx');
    	searchBinding($search_xklx);
    }

    function searchBinding($search) {
        $search.off('change').on('change', function(event) {            
            var courseType = $(event.currentTarget).attr('courseType');
            if (courseType == 'FAWKC') {
            	//切换上课年级院系时渲染专业
            	if($search.hasClass('search_yx') || $search.hasClass('search_nj')){
            		initSkzy();
            	}
                unProgramPageNumber = 0;
                CVUnProgramCourse.listReload();
            } else if (courseType == 'TJKC') {
                recommendPageNumber = 0;
                CVRecommendCourse.listReload();
            } else if (courseType == 'FANKC') {
                programPageNumber = 0;
                CVProgramCourse.listReload();
            } else if (courseType == 'XGXK') {
                publicPageNumber = 0;
                CVPublicCourse.listReload();
            } else if (courseType == 'CXKC') {
                retakePageNumber = 0;
                CVRetakeCourse.listReload();
            } else if (courseType == 'TYKC') {
                sportPageNumber = 0;
                CVSportCourse.listReload();
            } else if (courseType == 'FXKC') {
            	//切换年级院系时渲染专业
            	if($search.hasClass('search_yx') || $search.hasClass('search_nj')){
            		initZy();
            	}
                minorPageNumber = 0;
                CVMinorCourse.listReload();
            } else if (courseType == 'QXKC') {
                schoolPageNumber = 0;
                CVSchoolCourse.listReload();
            }
        });
    }

})(window.CVBindSearch = window.CVBindSearch || {});
/**
 * 页面初始化入口
 */
$(function() {
    // 初始化菜单控制
    initMenuControl();
    // 页头
    CVPageHead.init();
    // 侧边栏的事件监听
    CVAside.eventsListen();
    // 查询已选课程数量
    querySelectCourseNum();
    // 初始化页脚信息
    xsxkpub.CVFotterMessage.init();
    // 绑定退课日志链接点击事件
    departureLogClickBinding();
    // 绑定搜索事件
    searchClickBinding();
    // 设置页脚固定在页面底部
    setContentMinHeight($('.main').children('article'));
    // 初始化引导步骤图
    CVGuideMap.init();
    // 提醒落选课程
    //remindUnSuccessfulCourse();
    CVOnlineTip.init();

    CVBindingEvents.init();

    CVBindSearch.initSearch();
});

function changeJcWdgyy(ele){
	var v = $(ele);
	var flag = v.val()=='1';
	v.parent().next().children(0).prop("disabled", flag);
	if(flag){
		v.parent().next().children(0).val("***");
	}
}